using Azure;

internal sealed class FeedbackRecordReaper(
    FeedbackRecordStore store,
    ILogger<FeedbackRecordReaper> logger) : BackgroundService
{
    private static readonly TimeSpan Interval = TimeSpan.FromHours(6);

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var deleted = await store.DeleteExpiredAsync(stoppingToken);
                if (deleted > 0)
                {
                    logger.LogInformation(
                        "Deleted {DeletedCount} expired actionable feedback records.",
                        deleted);
                }
            }
            catch (OperationCanceledException) when (stoppingToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception exception)
            {
                logger.LogWarning(
                    exception,
                    "Could not delete expired actionable feedback records.");
            }

            await Task.Delay(Interval, stoppingToken);
        }
    }
}
