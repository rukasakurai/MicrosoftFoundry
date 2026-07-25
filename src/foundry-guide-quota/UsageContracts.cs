namespace FoundryGuide.Quota;

public sealed record UsageHistoryPoint(
    DateOnly Day,
    string Model,
    long PromptTokens,
    long CompletionTokens,
    long TotalTokens);

public sealed record UsageSnapshot(
    string Approach,
    string SubscriptionId,
    DateTimeOffset PeriodStart,
    DateTimeOffset PeriodEnd,
    long Limit,
    long Used,
    long Reserved,
    long Remaining,
    DateTimeOffset ObservedAt,
    string Consistency,
    IReadOnlyList<UsageHistoryPoint> History);

public sealed record QuotaPeriod(string Key, DateTimeOffset Start, DateTimeOffset End)
{
    public static QuotaPeriod Monthly(DateTimeOffset timestamp)
    {
        var utc = timestamp.UtcDateTime;
        var start = new DateTimeOffset(
            utc.Year,
            utc.Month,
            1,
            0,
            0,
            0,
            TimeSpan.Zero);
        return new QuotaPeriod(start.ToString("yyyyMM"), start, start.AddMonths(1));
    }

    public static QuotaPeriod FromKey(string key)
    {
        if (key.Length != 6
            || !int.TryParse(key[..4], out var year)
            || !int.TryParse(key[4..], out var month)
            || month is < 1 or > 12)
        {
            throw new InvalidOperationException($"Invalid quota period key: {key}");
        }

        var start = new DateTimeOffset(year, month, 1, 0, 0, 0, TimeSpan.Zero);
        return new QuotaPeriod(key, start, start.AddMonths(1));
    }
}

public sealed record QuotaReservation(
    string SubscriptionId,
    string ReservationId,
    long ReservedTokens,
    QuotaPeriod Period,
    DateTimeOffset ExpiresAt);

public sealed record ReservationResult(
    bool Accepted,
    QuotaReservation? Reservation,
    UsageSnapshot Usage);
