namespace FoundryGuide.Quota;

public sealed record QuotaLedgerOptions(
    long StrictTokenQuota,
    TimeSpan ReservationTtl,
    bool IncludeHistory = true);
