using Azure;
using Azure.Data.Tables;

internal sealed record FeedbackRecord(
    int Rating,
    string Outcome,
    string Reason,
    string AgentName,
    string AgentVersion,
    string TraceParent,
    string ResponseId,
    string UserIsolationKey,
    string ChatIsolationKey,
    string InputSha256,
    string DisplayedTextSha256);

internal interface IFeedbackRecordStore
{
    Task<string> SaveAsync(
        string feedbackId,
        FeedbackRecord record,
        CancellationToken cancellationToken);
}

internal sealed class FeedbackRecordStore(
    TableClient table,
    FoundryGuideFeedbackOptions options,
    TimeProvider timeProvider) : IFeedbackRecordStore
{
    internal const string PartitionKey = "feedback";

    public async Task<string> SaveAsync(
        string feedbackId,
        FeedbackRecord record,
        CancellationToken cancellationToken)
    {
        var submittedAt = timeProvider.GetUtcNow();
        try
        {
            await table.AddEntityAsync(
                new FeedbackRecordEntity
                {
                    PartitionKey = PartitionKey,
                    RowKey = feedbackId,
                    SubmittedAt = submittedAt,
                    ExpiresAt = submittedAt.Add(options.Retention),
                    Rating = record.Rating,
                    Outcome = record.Outcome,
                    Reason = record.Reason,
                    AgentName = record.AgentName,
                    AgentVersion = record.AgentVersion,
                    TraceParent = record.TraceParent,
                    ResponseId = record.ResponseId,
                    UserIsolationKey = record.UserIsolationKey,
                    ChatIsolationKey = record.ChatIsolationKey,
                    InputSha256 = record.InputSha256,
                    DisplayedTextSha256 = record.DisplayedTextSha256,
                    SchemaVersion = 2,
                },
                cancellationToken);
        }
        catch (RequestFailedException exception) when (exception.Status == 409)
        {
            // The one-time feedback token is also the durable idempotency key.
        }

        return feedbackId;
    }

    internal async Task<int> DeleteExpiredAsync(
        CancellationToken cancellationToken)
    {
        var now = timeProvider.GetUtcNow();
        var deleted = 0;
        await foreach (var entity in table.QueryAsync<FeedbackRecordEntity>(
            entity => entity.PartitionKey == PartitionKey && entity.ExpiresAt <= now,
            cancellationToken: cancellationToken))
        {
            await table.DeleteEntityAsync(
                entity.PartitionKey,
                entity.RowKey,
                ETag.All,
                cancellationToken);
            deleted++;
        }

        return deleted;
    }

    internal sealed class FeedbackRecordEntity : ITableEntity
    {
        public required string PartitionKey { get; set; }

        public required string RowKey { get; set; }

        public DateTimeOffset? Timestamp { get; set; }

        public ETag ETag { get; set; }

        public DateTimeOffset SubmittedAt { get; set; }

        public DateTimeOffset ExpiresAt { get; set; }

        public int Rating { get; set; }

        public string Outcome { get; set; } = string.Empty;

        public string Reason { get; set; } = string.Empty;

        public string AgentName { get; set; } = string.Empty;

        public string AgentVersion { get; set; } = string.Empty;

        public string TraceParent { get; set; } = string.Empty;

        public string ResponseId { get; set; } = string.Empty;

        public string UserIsolationKey { get; set; } = string.Empty;

        public string ChatIsolationKey { get; set; } = string.Empty;

        public string InputSha256 { get; set; } = string.Empty;

        public string DisplayedTextSha256 { get; set; } = string.Empty;

        public int SchemaVersion { get; set; }
    }
}
