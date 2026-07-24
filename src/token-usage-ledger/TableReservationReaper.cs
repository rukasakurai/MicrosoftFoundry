using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

public sealed class TableReservationReaper(
    TableQuotaLedger ledger,
    TimeProvider timeProvider,
    ILogger<TableReservationReaper> logger) : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromSeconds(30);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await ledger.ReapAllExpiredAsync(
                    timeProvider.GetUtcNow(),
                    stoppingToken);
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception exception)
            {
                logger.LogWarning(exception, "Failed to sweep expired quota reservations.");
            }

            await Task.Delay(Interval, stoppingToken);
        }
    }
}
