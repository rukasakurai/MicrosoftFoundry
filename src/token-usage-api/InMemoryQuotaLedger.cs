using System.Collections.Concurrent;

internal sealed class InMemoryQuotaLedger(
    TokenUsageOptions options,
    TimeProvider timeProvider) : IQuotaLedger
{
    private readonly ConcurrentDictionary<string, SubscriptionState> states = new();

    public async Task<ReservationResult> TryReserveAsync(
        string subscriptionId,
        long tokens,
        string model,
        CancellationToken cancellationToken)
    {
        var state = states.GetOrAdd(subscriptionId, _ => new SubscriptionState());
        await state.Lock.WaitAsync(cancellationToken);
        try
        {
            var now = timeProvider.GetUtcNow();
            var period = QuotaPeriod.Monthly(now);
            state.ResetIfNeeded(period);
            state.ReleaseExpired(now);

            if (state.Used + state.Reserved + tokens > options.StrictTokenQuota)
            {
                return new ReservationResult(
                    false,
                    null,
                    state.Snapshot(subscriptionId, options.StrictTokenQuota, now));
            }

            var reservation = new QuotaReservation(
                subscriptionId,
                Guid.NewGuid().ToString("N"),
                tokens,
                period,
                now.Add(options.ReservationTtl));
            state.Reservations.Add(
                reservation.ReservationId,
                new PendingReservation(reservation, model));
            state.Reserved += tokens;

            return new ReservationResult(
                true,
                reservation,
                state.Snapshot(subscriptionId, options.StrictTokenQuota, now));
        }
        finally
        {
            state.Lock.Release();
        }
    }

    public async Task<UsageSnapshot> CompleteAsync(
        QuotaReservation reservation,
        long actualTokens,
        long promptTokens,
        long completionTokens,
        string model,
        CancellationToken cancellationToken)
    {
        var state = states.GetOrAdd(reservation.SubscriptionId, _ => new SubscriptionState());
        await state.Lock.WaitAsync(cancellationToken);
        try
        {
            var now = timeProvider.GetUtcNow();
            state.ResetIfNeeded(QuotaPeriod.Monthly(now));

            if (!state.Reservations.TryGetValue(reservation.ReservationId, out var pending))
            {
                throw new InvalidOperationException("The quota reservation no longer exists.");
            }

            if (pending.Completed)
            {
                return state.Snapshot(
                    reservation.SubscriptionId,
                    options.StrictTokenQuota,
                    now);
            }

            state.Reserved -= reservation.ReservedTokens;
            state.Used += actualTokens;
            pending.Completed = true;
            pending.ActualTokens = actualTokens;
            pending.PromptTokens = promptTokens;
            pending.CompletionTokens = completionTokens;
            pending.Model = model;
            pending.CompletedAt = now;

            return state.Snapshot(
                reservation.SubscriptionId,
                options.StrictTokenQuota,
                now);
        }
        finally
        {
            state.Lock.Release();
        }
    }

    public async Task<UsageSnapshot> GetUsageAsync(
        string subscriptionId,
        CancellationToken cancellationToken)
    {
        var state = states.GetOrAdd(subscriptionId, _ => new SubscriptionState());
        await state.Lock.WaitAsync(cancellationToken);
        try
        {
            var now = timeProvider.GetUtcNow();
            state.ResetIfNeeded(QuotaPeriod.Monthly(now));
            state.ReleaseExpired(now);
            return state.Snapshot(subscriptionId, options.StrictTokenQuota, now);
        }
        finally
        {
            state.Lock.Release();
        }
    }

    private sealed class SubscriptionState
    {
        internal SemaphoreSlim Lock { get; } = new(1, 1);

        internal QuotaPeriod Period { get; private set; } =
            QuotaPeriod.Monthly(DateTimeOffset.UtcNow);

        internal long Used { get; set; }

        internal long Reserved { get; set; }

        internal Dictionary<string, PendingReservation> Reservations { get; } = [];

        internal void ResetIfNeeded(QuotaPeriod period)
        {
            if (Period.Key == period.Key)
            {
                return;
            }

            Period = period;
            Used = 0;
            Reserved = 0;
            Reservations.Clear();
        }

        internal void ReleaseExpired(DateTimeOffset now)
        {
            foreach (var pending in Reservations.Values.Where(item =>
                         !item.Completed && item.Reservation.ExpiresAt <= now))
            {
                pending.Completed = true;
                Reserved -= pending.Reservation.ReservedTokens;
                Used += pending.Reservation.ReservedTokens;
                pending.ActualTokens = pending.Reservation.ReservedTokens;
                pending.CompletedAt = now;
            }
        }

        internal UsageSnapshot Snapshot(
            string subscriptionId,
            long limit,
            DateTimeOffset now)
        {
            var history = Reservations.Values
                .Where(item => item.CompletedAt is not null)
                .GroupBy(item => new
                {
                    Day = DateOnly.FromDateTime(item.CompletedAt!.Value.UtcDateTime),
                    item.Model,
                })
                .Select(group => new UsageHistoryPoint(
                    group.Key.Day,
                    group.Key.Model,
                    group.Sum(item => item.PromptTokens),
                    group.Sum(item => item.CompletionTokens),
                    group.Sum(item => item.ActualTokens)))
                .OrderBy(item => item.Day)
                .ThenBy(item => item.Model, StringComparer.Ordinal)
                .ToArray();

            return new UsageSnapshot(
                "strict",
                subscriptionId,
                Period.Start,
                Period.End,
                limit,
                Used,
                Reserved,
                Math.Max(0, limit - Used - Reserved),
                now,
                "authoritative",
                history);
        }
    }

    private sealed class PendingReservation(
        QuotaReservation reservation,
        string model)
    {
        internal QuotaReservation Reservation { get; } = reservation;

        internal string Model { get; set; } = model;

        internal bool Completed { get; set; }

        internal long ActualTokens { get; set; }

        internal long PromptTokens { get; set; }

        internal long CompletionTokens { get; set; }

        internal DateTimeOffset? CompletedAt { get; set; }
    }
}
