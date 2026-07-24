using Xunit;

public sealed class InMemoryQuotaLedgerTests
{
    [Fact]
    public async Task ConcurrentReservationsCannotExceedQuota()
    {
        var time = new TestTimeProvider(new DateTimeOffset(2026, 7, 23, 0, 0, 0, TimeSpan.Zero));
        var ledger = new InMemoryQuotaLedger(CreateOptions(), time);
        var cancellationToken = TestContext.Current.CancellationToken;

        var attempts = await Task.WhenAll(
            Enumerable.Range(0, 20)
                .Select(_ => ledger.TryReserveAsync(
                    "consumer-a",
                    300,
                    "model",
                    cancellationToken)));

        Assert.Equal(3, attempts.Count(result => result.Accepted));
        var usage = await ledger.GetUsageAsync("consumer-a", cancellationToken);
        Assert.Equal(900, usage.Reserved);
        Assert.Equal(100, usage.Remaining);
    }

    [Fact]
    public async Task SettlementReplacesReservationWithActualUsage()
    {
        var time = new TestTimeProvider(new DateTimeOffset(2026, 7, 23, 0, 0, 0, TimeSpan.Zero));
        var ledger = new InMemoryQuotaLedger(CreateOptions(), time);
        var cancellationToken = TestContext.Current.CancellationToken;
        var result = await ledger.TryReserveAsync(
            "consumer-a",
            300,
            "model",
            cancellationToken);

        var usage = await ledger.CompleteAsync(
            Assert.IsType<QuotaReservation>(result.Reservation),
            actualTokens: 40,
            promptTokens: 25,
            completionTokens: 15,
            model: "model",
            cancellationToken);

        Assert.Equal(40, usage.Used);
        Assert.Equal(0, usage.Reserved);
        Assert.Equal(960, usage.Remaining);
        var history = Assert.Single(usage.History);
        Assert.Equal(25, history.PromptTokens);
        Assert.Equal(15, history.CompletionTokens);
        Assert.Equal(40, history.TotalTokens);
    }

    [Fact]
    public async Task ExpiredReservationsAreChargedConservatively()
    {
        var time = new TestTimeProvider(new DateTimeOffset(2026, 7, 23, 0, 0, 0, TimeSpan.Zero));
        var ledger = new InMemoryQuotaLedger(CreateOptions(), time);
        var cancellationToken = TestContext.Current.CancellationToken;
        await ledger.TryReserveAsync("consumer-a", 300, "model", cancellationToken);

        time.Advance(TimeSpan.FromMinutes(4));
        var usage = await ledger.GetUsageAsync("consumer-a", cancellationToken);

        Assert.Equal(300, usage.Used);
        Assert.Equal(0, usage.Reserved);
        Assert.Equal(700, usage.Remaining);
    }

    [Fact]
    public async Task NewMonthStartsNewQuotaPeriod()
    {
        var time = new TestTimeProvider(new DateTimeOffset(2026, 7, 31, 23, 59, 0, TimeSpan.Zero));
        var ledger = new InMemoryQuotaLedger(CreateOptions(), time);
        var cancellationToken = TestContext.Current.CancellationToken;
        var result = await ledger.TryReserveAsync(
            "consumer-a",
            300,
            "model",
            cancellationToken);
        await ledger.CompleteAsync(
            Assert.IsType<QuotaReservation>(result.Reservation),
            40,
            25,
            15,
            "model",
            cancellationToken);

        time.Advance(TimeSpan.FromMinutes(2));
        var usage = await ledger.GetUsageAsync("consumer-a", cancellationToken);

        Assert.Equal(new DateTimeOffset(2026, 8, 1, 0, 0, 0, TimeSpan.Zero), usage.PeriodStart);
        Assert.Equal(0, usage.Used);
        Assert.Equal(1_000, usage.Remaining);
    }

    private static QuotaLedgerOptions CreateOptions() =>
        new(1_000, TimeSpan.FromMinutes(3));

    private sealed class TestTimeProvider(DateTimeOffset now) : TimeProvider
    {
        private DateTimeOffset current = now;

        public override DateTimeOffset GetUtcNow() => current;

        internal void Advance(TimeSpan amount) => current = current.Add(amount);
    }
}
