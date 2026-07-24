using System.Security.Cryptography;
using System.Text;
using Azure;
using Azure.Data.Tables;
using Microsoft.Extensions.Logging;

public sealed class TableQuotaLedger(
    TableClient table,
    QuotaLedgerOptions options,
    TimeProvider timeProvider,
    ILogger<TableQuotaLedger> logger) : IQuotaLedger
{
    private const int MaxAttempts = 12;

    public async Task<ReservationResult> TryReserveAsync(
        string subscriptionId,
        long tokens,
        string model,
        CancellationToken cancellationToken)
    {
        var now = timeProvider.GetUtcNow();
        var period = QuotaPeriod.Monthly(now);
        var partitionKey = PartitionKey(subscriptionId);
        await ReapExpiredAsync(partitionKey, now, cancellationToken);

        for (var attempt = 0; attempt < MaxAttempts; attempt++)
        {
            var summary = await GetOrCreateSummaryAsync(
                partitionKey,
                subscriptionId,
                period,
                cancellationToken);
            if (summary.UsedTokens + summary.ReservedTokens + tokens > options.StrictTokenQuota)
            {
                return new ReservationResult(
                    false,
                    null,
                    await SnapshotAsync(summary, subscriptionId, period, now, cancellationToken));
            }

            var reservation = new QuotaReservation(
                subscriptionId,
                Guid.NewGuid().ToString("N"),
                tokens,
                period,
                now.Add(options.ReservationTtl));
            var entity = ReservationEntity.Pending(partitionKey, reservation, model, now);

            summary.Limit = options.StrictTokenQuota;
            summary.ReservedTokens += tokens;
            summary.UpdatedAt = now;

            try
            {
                await table.SubmitTransactionAsync(
                    [
                        new TableTransactionAction(
                            TableTransactionActionType.UpdateReplace,
                            summary,
                            summary.ETag),
                        new TableTransactionAction(
                            TableTransactionActionType.Add,
                            entity),
                    ],
                    cancellationToken);

                return new ReservationResult(
                    true,
                    reservation,
                    await SnapshotAsync(summary, subscriptionId, period, now, cancellationToken));
            }
            catch (RequestFailedException exception) when (exception.Status is 409 or 412)
            {
                await DelayForConflictAsync(attempt, cancellationToken);
            }
        }

        throw new InvalidOperationException("Could not reserve quota after repeated concurrent updates.");
    }

    public async Task<UsageSnapshot> CompleteAsync(
        QuotaReservation reservation,
        long actualTokens,
        long promptTokens,
        long completionTokens,
        string model,
        CancellationToken cancellationToken)
    {
        var partitionKey = PartitionKey(reservation.SubscriptionId);
        var reservationRowKey = ReservationEntity.RowKeyFor(
            reservation.Period,
            reservation.ReservationId);

        for (var attempt = 0; attempt < MaxAttempts; attempt++)
        {
            var summaryResponse = await table.GetEntityAsync<QuotaSummaryEntity>(
                partitionKey,
                QuotaSummaryEntity.RowKeyFor(reservation.Period),
                cancellationToken: cancellationToken);
            var reservationResponse = await table.GetEntityAsync<ReservationEntity>(
                partitionKey,
                reservationRowKey,
                cancellationToken: cancellationToken);
            var summary = summaryResponse.Value;
            var entity = reservationResponse.Value;

            if (entity.State == ReservationEntity.CompletedState)
            {
                return await SnapshotAsync(
                    summary,
                    reservation.SubscriptionId,
                    reservation.Period,
                    timeProvider.GetUtcNow(),
                    cancellationToken);
            }

            if (entity.State != ReservationEntity.PendingState)
            {
                throw new InvalidOperationException(
                    $"Reservation {reservation.ReservationId} is {entity.State}.");
            }

            var now = timeProvider.GetUtcNow();
            summary.ReservedTokens -= entity.ReservedTokens;
            summary.UsedTokens += actualTokens;
            summary.UpdatedAt = now;
            entity.State = ReservationEntity.CompletedState;
            entity.ActualTokens = actualTokens;
            entity.PromptTokens = promptTokens;
            entity.CompletionTokens = completionTokens;
            entity.Model = model;
            entity.CompletedAt = now;

            try
            {
                await table.SubmitTransactionAsync(
                    [
                        new TableTransactionAction(
                            TableTransactionActionType.UpdateReplace,
                            summary,
                            summary.ETag),
                        new TableTransactionAction(
                            TableTransactionActionType.UpdateReplace,
                            entity,
                            entity.ETag),
                    ],
                    cancellationToken);

                return await SnapshotAsync(
                    summary,
                    reservation.SubscriptionId,
                    reservation.Period,
                    now,
                    cancellationToken);
            }
            catch (RequestFailedException exception) when (exception.Status is 409 or 412)
            {
                await DelayForConflictAsync(attempt, cancellationToken);
            }
        }

        throw new InvalidOperationException("Could not settle quota after repeated concurrent updates.");
    }

    public async Task<UsageSnapshot> GetUsageAsync(
        string subscriptionId,
        CancellationToken cancellationToken)
    {
        var now = timeProvider.GetUtcNow();
        var period = QuotaPeriod.Monthly(now);
        var partitionKey = PartitionKey(subscriptionId);
        await ReapExpiredAsync(partitionKey, now, cancellationToken);
        var summary = await GetOrCreateSummaryAsync(
            partitionKey,
            subscriptionId,
            period,
            cancellationToken);
        return await SnapshotAsync(summary, subscriptionId, period, now, cancellationToken);
    }

    private async Task<QuotaSummaryEntity> GetOrCreateSummaryAsync(
        string partitionKey,
        string subscriptionId,
        QuotaPeriod period,
        CancellationToken cancellationToken)
    {
        var response = await table.GetEntityIfExistsAsync<QuotaSummaryEntity>(
            partitionKey,
            QuotaSummaryEntity.RowKeyFor(period),
            cancellationToken: cancellationToken);
        if (response.HasValue)
        {
            return response.Value!;
        }

        var entity = QuotaSummaryEntity.Create(
            partitionKey,
            subscriptionId,
            period,
            options.StrictTokenQuota,
            timeProvider.GetUtcNow());
        try
        {
            await table.AddEntityAsync(entity, cancellationToken);
            return (await table.GetEntityAsync<QuotaSummaryEntity>(
                partitionKey,
                QuotaSummaryEntity.RowKeyFor(period),
                cancellationToken: cancellationToken)).Value;
        }
        catch (RequestFailedException exception) when (exception.Status == 409)
        {
            return (await table.GetEntityAsync<QuotaSummaryEntity>(
                partitionKey,
                QuotaSummaryEntity.RowKeyFor(period),
                cancellationToken: cancellationToken)).Value;
        }
    }

    private async Task ReapExpiredAsync(
        string partitionKey,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var filter = TableClient.CreateQueryFilter(
            $"PartitionKey eq {partitionKey} and State eq {ReservationEntity.PendingState} and ExpiresAt le {now}");
        var expired = new List<ReservationEntity>();
        await foreach (var entity in table.QueryAsync<ReservationEntity>(
                           filter,
                           maxPerPage: 25,
                           cancellationToken: cancellationToken))
        {
            expired.Add(entity);
        }

        foreach (var entity in expired)
        {
            await ChargeExpiredAsync(
                entity,
                QuotaPeriod.FromKey(entity.PeriodKey),
                cancellationToken);
        }
    }

    public async Task ReapAllExpiredAsync(
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        var filter = TableClient.CreateQueryFilter(
            $"State eq {ReservationEntity.PendingState} and ExpiresAt le {now}");
        var expired = new List<ReservationEntity>();
        await foreach (var entity in table.QueryAsync<ReservationEntity>(
                           filter,
                           maxPerPage: 100,
                           cancellationToken: cancellationToken))
        {
            expired.Add(entity);
        }

        foreach (var entity in expired)
        {
            await ChargeExpiredAsync(
                entity,
                QuotaPeriod.FromKey(entity.PeriodKey),
                cancellationToken);
        }
    }

    private async Task ChargeExpiredAsync(
        ReservationEntity expired,
        QuotaPeriod period,
        CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < MaxAttempts; attempt++)
        {
            var summary = (await table.GetEntityAsync<QuotaSummaryEntity>(
                expired.PartitionKey,
                QuotaSummaryEntity.RowKeyFor(period),
                cancellationToken: cancellationToken)).Value;
            var current = await table.GetEntityIfExistsAsync<ReservationEntity>(
                expired.PartitionKey,
                expired.RowKey,
                cancellationToken: cancellationToken);

            if (!current.HasValue)
            {
                return;
            }

            var entity = current.Value!;
            if (entity.State != ReservationEntity.PendingState)
            {
                return;
            }

            var now = timeProvider.GetUtcNow();
            if (entity.ExpiresAt > now)
            {
                return;
            }

            summary.ReservedTokens -= entity.ReservedTokens;
            summary.UsedTokens += entity.ReservedTokens;
            summary.UpdatedAt = now;
            entity.State = ReservationEntity.CompletedState;
            entity.ActualTokens = entity.ReservedTokens;
            entity.CompletedAt = now;

            try
            {
                await table.SubmitTransactionAsync(
                    [
                        new TableTransactionAction(
                            TableTransactionActionType.UpdateReplace,
                            summary,
                            summary.ETag),
                        new TableTransactionAction(
                            TableTransactionActionType.UpdateReplace,
                            entity,
                            entity.ETag),
                    ],
                    cancellationToken);
                logger.LogWarning(
                    "Charged the full amount for expired quota reservation {ReservationId}.",
                    entity.ReservationId);
                return;
            }
            catch (RequestFailedException exception) when (exception.Status is 409 or 412)
            {
                await DelayForConflictAsync(attempt, cancellationToken);
            }
        }

        throw new InvalidOperationException("Could not release an expired reservation.");
    }

    private async Task<UsageSnapshot> SnapshotAsync(
        QuotaSummaryEntity summary,
        string subscriptionId,
        QuotaPeriod period,
        DateTimeOffset now,
        CancellationToken cancellationToken)
    {
        IReadOnlyList<UsageHistoryPoint> history = [];
        if (options.IncludeHistory)
        {
            var filter = TableClient.CreateQueryFilter(
                $"PartitionKey eq {summary.PartitionKey} and PeriodKey eq {period.Key} and State eq {ReservationEntity.CompletedState}");
            var completed = new List<ReservationEntity>();
            await foreach (var entity in table.QueryAsync<ReservationEntity>(
                               filter,
                               cancellationToken: cancellationToken))
            {
                completed.Add(entity);
            }

            history = completed
                .Where(entity => entity.CompletedAt is not null)
                .GroupBy(entity => new
                {
                    Day = DateOnly.FromDateTime(entity.CompletedAt!.Value.UtcDateTime),
                    entity.Model,
                })
                .Select(group => new UsageHistoryPoint(
                    group.Key.Day,
                    group.Key.Model,
                    group.Sum(entity => entity.PromptTokens),
                    group.Sum(entity => entity.CompletionTokens),
                    group.Sum(entity => entity.ActualTokens)))
                .OrderBy(item => item.Day)
                .ThenBy(item => item.Model, StringComparer.Ordinal)
                .ToArray();
        }

        return new UsageSnapshot(
            "strict",
            subscriptionId,
            period.Start,
            period.End,
            options.StrictTokenQuota,
            summary.UsedTokens,
            summary.ReservedTokens,
            Math.Max(
                0,
                options.StrictTokenQuota - summary.UsedTokens - summary.ReservedTokens),
            now,
            "authoritative",
            history);
    }

    private static string PartitionKey(string subscriptionId) =>
        Convert.ToHexStringLower(SHA256.HashData(Encoding.UTF8.GetBytes(subscriptionId)));

    private static Task DelayForConflictAsync(int attempt, CancellationToken cancellationToken) =>
        Task.Delay(TimeSpan.FromMilliseconds(10 * (attempt + 1)), cancellationToken);

    private sealed class QuotaSummaryEntity : ITableEntity
    {
        public required string PartitionKey { get; set; }

        public required string RowKey { get; set; }

        public DateTimeOffset? Timestamp { get; set; }

        public ETag ETag { get; set; }

        public required string SubscriptionId { get; set; }

        public required string PeriodKey { get; set; }

        public DateTimeOffset PeriodStart { get; set; }

        public DateTimeOffset PeriodEnd { get; set; }

        public long Limit { get; set; }

        public long UsedTokens { get; set; }

        public long ReservedTokens { get; set; }

        public DateTimeOffset UpdatedAt { get; set; }

        internal static string RowKeyFor(QuotaPeriod period) => $"quota:{period.Key}";

        internal static QuotaSummaryEntity Create(
            string partitionKey,
            string subscriptionId,
            QuotaPeriod period,
            long limit,
            DateTimeOffset now) =>
            new()
            {
                PartitionKey = partitionKey,
                RowKey = RowKeyFor(period),
                SubscriptionId = subscriptionId,
                PeriodKey = period.Key,
                PeriodStart = period.Start,
                PeriodEnd = period.End,
                Limit = limit,
                UpdatedAt = now,
            };
    }

    private sealed class ReservationEntity : ITableEntity
    {
        internal const string PendingState = "Pending";
        internal const string CompletedState = "Completed";

        public required string PartitionKey { get; set; }

        public required string RowKey { get; set; }

        public DateTimeOffset? Timestamp { get; set; }

        public ETag ETag { get; set; }

        public required string ReservationId { get; set; }

        public required string PeriodKey { get; set; }

        public required string State { get; set; }

        public required string Model { get; set; }

        public long ReservedTokens { get; set; }

        public long ActualTokens { get; set; }

        public long PromptTokens { get; set; }

        public long CompletionTokens { get; set; }

        public DateTimeOffset ExpiresAt { get; set; }

        public DateTimeOffset? CompletedAt { get; set; }

        internal static string RowKeyFor(QuotaPeriod period, string reservationId) =>
            $"reservation:{period.Key}:{reservationId}";

        internal static ReservationEntity Pending(
            string partitionKey,
            QuotaReservation reservation,
            string model,
            DateTimeOffset now) =>
            new()
            {
                PartitionKey = partitionKey,
                RowKey = RowKeyFor(reservation.Period, reservation.ReservationId),
                ReservationId = reservation.ReservationId,
                PeriodKey = reservation.Period.Key,
                State = PendingState,
                Model = model,
                ReservedTokens = reservation.ReservedTokens,
                ExpiresAt = reservation.ExpiresAt,
                CompletedAt = null,
            };
    }
}
