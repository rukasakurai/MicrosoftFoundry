public interface IQuotaLedger
{
    Task<ReservationResult> TryReserveAsync(
        string subscriptionId,
        long tokens,
        string model,
        CancellationToken cancellationToken);

    Task<UsageSnapshot> CompleteAsync(
        QuotaReservation reservation,
        long actualTokens,
        long promptTokens,
        long completionTokens,
        string model,
        CancellationToken cancellationToken);

    Task<UsageSnapshot> GetUsageAsync(
        string subscriptionId,
        CancellationToken cancellationToken);
}
