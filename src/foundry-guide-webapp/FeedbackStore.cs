using Azure;
using Azure.Core;
using Azure.Data.Tables;

internal sealed class FeedbackStore(
    TokenCredential credential,
    IConfiguration configuration)
{
    private const string PartitionKey = "feedback";
    private readonly TableClient _table = new TableServiceClient(
        new Uri(Require(configuration["FEEDBACK_STORAGE_TABLE_ENDPOINT"], "FEEDBACK_STORAGE_TABLE_ENDPOINT")),
        credential).GetTableClient("FoundryGuideFeedback");
    private readonly SemaphoreSlim _initializationLock = new(1, 1);
    private bool _initialized;

    internal async Task<string> SaveAsync(
        string traceParent,
        string responseId,
        CancellationToken cancellationToken)
    {
        await EnsureCreatedAsync(cancellationToken);
        await DeleteExpiredAsync(cancellationToken);

        var token = Guid.NewGuid().ToString("N");
        await _table.AddEntityAsync(
            new FeedbackEntity
            {
                PartitionKey = PartitionKey,
                RowKey = token,
                TraceParent = traceParent,
                ResponseId = responseId,
                ExpiresAt = DateTimeOffset.UtcNow.AddHours(24),
            },
            cancellationToken);
        return token;
    }

    internal async Task<FeedbackCorrelation?> ConsumeAsync(
        string token,
        CancellationToken cancellationToken)
    {
        await EnsureCreatedAsync(cancellationToken);
        var result = await _table.GetEntityIfExistsAsync<FeedbackEntity>(
            PartitionKey,
            token,
            cancellationToken: cancellationToken);

        if (!result.HasValue)
        {
            return null;
        }

        var entity = result.Value!;
        try
        {
            await _table.DeleteEntityAsync(
                entity.PartitionKey,
                entity.RowKey,
                entity.ETag,
                cancellationToken);
        }
        catch (RequestFailedException exception) when (exception.Status is 404 or 412)
        {
            return null;
        }

        return entity.ExpiresAt > DateTimeOffset.UtcNow
            ? new FeedbackCorrelation(entity.TraceParent, entity.ResponseId)
            : null;
    }

    private async Task DeleteExpiredAsync(CancellationToken cancellationToken)
    {
        var now = DateTimeOffset.UtcNow;
        await foreach (var entity in _table.QueryAsync<FeedbackEntity>(
            item => item.PartitionKey == PartitionKey && item.ExpiresAt <= now,
            maxPerPage: 25,
            cancellationToken: cancellationToken))
        {
            await _table.DeleteEntityAsync(
                entity.PartitionKey,
                entity.RowKey,
                entity.ETag,
                cancellationToken);
        }
    }

    private async Task EnsureCreatedAsync(CancellationToken cancellationToken)
    {
        if (_initialized)
        {
            return;
        }

        await _initializationLock.WaitAsync(cancellationToken);
        try
        {
            if (!_initialized)
            {
                await _table.CreateIfNotExistsAsync(cancellationToken);
                _initialized = true;
            }
        }
        finally
        {
            _initializationLock.Release();
        }
    }

    private static string Require(string? value, string name) =>
        string.IsNullOrWhiteSpace(value)
            ? throw new InvalidOperationException($"{name} is required.")
            : value;
}

internal sealed record FeedbackCorrelation(string TraceParent, string ResponseId);

internal sealed class FeedbackEntity : ITableEntity
{
    public required string PartitionKey { get; set; }
    public required string RowKey { get; set; }
    public required string TraceParent { get; set; }
    public required string ResponseId { get; set; }
    public DateTimeOffset ExpiresAt { get; set; }
    public DateTimeOffset? Timestamp { get; set; }
    public ETag ETag { get; set; }
}
