using Azure;
using Azure.Data.Tables;

internal enum BeginTurnFailure
{
    None,
    OutOfSync,
    Busy,
    ContextLimit,
}

internal sealed record ConversationTurnLease(
    string PartitionKey,
    string RowKey,
    string TurnId,
    long ReservationTokens);

internal sealed record BeginTurnResult(
    ConversationTurnLease? Lease,
    BeginTurnFailure Failure);

internal sealed class GuideConversationStore(
    TableClient table,
    FoundryGuideQuotaOptions options,
    TimeProvider timeProvider)
{
    private const int MaxAttempts = 12;

    internal async Task<BeginTurnResult> TryBeginTurnAsync(
        string subject,
        string chatId,
        string? previousResponseId,
        int inputBytes,
        CancellationToken cancellationToken)
    {
        var partitionKey = GuideIdentity.Hash(subject);
        var rowKey = $"conversation:{GuideIdentity.Hash(chatId)}";

        for (var attempt = 0; attempt < MaxAttempts; attempt++)
        {
            var now = timeProvider.GetUtcNow();
            var response = await table.GetEntityIfExistsAsync<ConversationEntity>(
                partitionKey,
                rowKey,
                cancellationToken: cancellationToken);
            var entity = response.HasValue ? response.Value! : null;

            if (entity is null)
            {
                if (!string.IsNullOrWhiteSpace(previousResponseId))
                {
                    return new BeginTurnResult(null, BeginTurnFailure.OutOfSync);
                }

                var reservationTokens = ReservationTokens(0, inputBytes);
                if (reservationTokens > options.MaxReservationTokens)
                {
                    return new BeginTurnResult(null, BeginTurnFailure.ContextLimit);
                }

                var turnId = Guid.NewGuid().ToString("N");
                entity = ConversationEntity.Create(
                    partitionKey,
                    rowKey,
                    turnId,
                    now.Add(options.ReservationTtl));
                try
                {
                    await table.AddEntityAsync(entity, cancellationToken);
                    return new BeginTurnResult(
                        new ConversationTurnLease(
                            partitionKey,
                            rowKey,
                            turnId,
                            reservationTokens),
                        BeginTurnFailure.None);
                }
                catch (RequestFailedException exception) when (exception.Status == 409)
                {
                    await DelayForConflictAsync(attempt, cancellationToken);
                    continue;
                }
            }

            if (entity.PendingUntil > now)
            {
                return new BeginTurnResult(null, BeginTurnFailure.Busy);
            }

            if (!MatchesPreviousResponse(entity.ResponseIdHash, previousResponseId))
            {
                return new BeginTurnResult(null, BeginTurnFailure.OutOfSync);
            }

            var tokens = ReservationTokens(entity.ContextTokens, inputBytes);
            if (tokens > options.MaxReservationTokens)
            {
                return new BeginTurnResult(null, BeginTurnFailure.ContextLimit);
            }

            var pendingTurnId = Guid.NewGuid().ToString("N");
            entity.PendingTurnId = pendingTurnId;
            entity.PendingUntil = now.Add(options.ReservationTtl);
            try
            {
                await table.UpdateEntityAsync(
                    entity,
                    entity.ETag,
                    TableUpdateMode.Replace,
                    cancellationToken);
                return new BeginTurnResult(
                    new ConversationTurnLease(
                        partitionKey,
                        rowKey,
                        pendingTurnId,
                        tokens),
                    BeginTurnFailure.None);
            }
            catch (RequestFailedException exception) when (exception.Status == 412)
            {
                await DelayForConflictAsync(attempt, cancellationToken);
            }
        }

        throw new InvalidOperationException(
            "Could not lock the chat after repeated concurrent updates.");
    }

    internal Task<bool> CompleteTurnAsync(
        ConversationTurnLease lease,
        string responseId,
        long contextTokens,
        CancellationToken cancellationToken) =>
        FinishTurnAsync(lease, GuideIdentity.Hash(responseId), contextTokens, cancellationToken);

    internal Task<bool> ReleaseTurnAsync(
        ConversationTurnLease lease,
        CancellationToken cancellationToken) =>
        FinishTurnAsync(lease, null, null, cancellationToken);

    private async Task<bool> FinishTurnAsync(
        ConversationTurnLease lease,
        string? responseIdHash,
        long? contextTokens,
        CancellationToken cancellationToken)
    {
        for (var attempt = 0; attempt < MaxAttempts; attempt++)
        {
            var response = await table.GetEntityIfExistsAsync<ConversationEntity>(
                lease.PartitionKey,
                lease.RowKey,
                cancellationToken: cancellationToken);
            if (!response.HasValue
                || !string.Equals(
                    response.Value!.PendingTurnId,
                    lease.TurnId,
                    StringComparison.Ordinal))
            {
                return false;
            }

            var entity = response.Value!;
            if (responseIdHash is not null && contextTokens.HasValue)
            {
                entity.ResponseIdHash = responseIdHash;
                entity.ContextTokens = contextTokens.Value;
            }

            entity.PendingTurnId = string.Empty;
            entity.PendingUntil = null;
            try
            {
                await table.UpdateEntityAsync(
                    entity,
                    entity.ETag,
                    TableUpdateMode.Replace,
                    cancellationToken);
                return true;
            }
            catch (RequestFailedException exception) when (exception.Status == 412)
            {
                await DelayForConflictAsync(attempt, cancellationToken);
            }
        }

        throw new InvalidOperationException(
            "Could not finish the chat turn after repeated concurrent updates.");
    }

    private long ReservationTokens(long contextTokens, int inputBytes) =>
        checked(
            contextTokens
            + inputBytes
            + options.MaxOutputTokens
            + options.SafetyPaddingTokens);

    private static bool MatchesPreviousResponse(
        string expectedHash,
        string? previousResponseId) =>
        string.IsNullOrEmpty(expectedHash)
            ? string.IsNullOrWhiteSpace(previousResponseId)
            : !string.IsNullOrWhiteSpace(previousResponseId)
              && string.Equals(
                  expectedHash,
                  GuideIdentity.Hash(previousResponseId),
                  StringComparison.Ordinal);

    private static Task DelayForConflictAsync(int attempt, CancellationToken cancellationToken) =>
        Task.Delay(TimeSpan.FromMilliseconds(10 * (attempt + 1)), cancellationToken);

    private sealed class ConversationEntity : ITableEntity
    {
        public required string PartitionKey { get; set; }

        public required string RowKey { get; set; }

        public DateTimeOffset? Timestamp { get; set; }

        public ETag ETag { get; set; }

        public string ResponseIdHash { get; set; } = string.Empty;

        public long ContextTokens { get; set; }

        public string PendingTurnId { get; set; } = string.Empty;

        public DateTimeOffset? PendingUntil { get; set; }

        internal static ConversationEntity Create(
            string partitionKey,
            string rowKey,
            string turnId,
            DateTimeOffset pendingUntil) =>
            new()
            {
                PartitionKey = partitionKey,
                RowKey = rowKey,
                PendingTurnId = turnId,
                PendingUntil = pendingUntil,
            };
    }
}
