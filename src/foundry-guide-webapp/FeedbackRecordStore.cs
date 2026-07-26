using Azure;
using Azure.Data.Tables;

internal sealed record FeedbackRecord(
    string Reason,
    string AgentName,
    string AgentVersion,
    string ResponseId,
    string UserIsolationKey,
    string ChatIsolationKey,
    string InputSha256,
    string DisplayedTextSha256);

internal interface IFeedbackRecordStore
{
    Task SaveAsync(
        string feedbackId,
        FeedbackRecord record);
}

internal sealed class FeedbackRecordStore(
    TableClient table,
    FoundryGuideFeedbackOptions options,
    TimeProvider timeProvider) : IFeedbackRecordStore
{
    internal const string PartitionKey = "feedback";
    internal const string TableName = "FoundryGuideFeedback";

    public async Task SaveAsync(
        string feedbackId,
        FeedbackRecord record)
    {
        var submittedAt = timeProvider.GetUtcNow();
        try
        {
            await table.AddEntityAsync(
                new FeedbackRecordEntity
                {
                    PartitionKey = PartitionKey,
                    RowKey = feedbackId,
                    ExpiresAt = submittedAt.Add(options.Retention),
                    Reason = record.Reason,
                    AgentName = record.AgentName,
                    AgentVersion = record.AgentVersion,
                    ResponseId = record.ResponseId,
                    UserIsolationKey = record.UserIsolationKey,
                    ChatIsolationKey = record.ChatIsolationKey,
                    InputSha256 = record.InputSha256,
                    DisplayedTextSha256 = record.DisplayedTextSha256,
                },
                CancellationToken.None);
        }
        catch (RequestFailedException exception) when (exception.Status == 409)
        {
            // The one-time feedback token is also the durable idempotency key.
        }
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

        public DateTimeOffset ExpiresAt { get; set; }

        public string Reason { get; set; } = string.Empty;

        public string AgentName { get; set; } = string.Empty;

        public string AgentVersion { get; set; } = string.Empty;

        public string ResponseId { get; set; } = string.Empty;

        public string UserIsolationKey { get; set; } = string.Empty;

        public string ChatIsolationKey { get; set; } = string.Empty;

        public string InputSha256 { get; set; } = string.Empty;

        public string DisplayedTextSha256 { get; set; } = string.Empty;
    }
}
