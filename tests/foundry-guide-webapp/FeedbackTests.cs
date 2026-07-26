using Azure;
using Microsoft.AspNetCore.Http;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Logging.Abstractions;
using Xunit;

public sealed class FeedbackTests
{
    private const string TraceParent =
        "00-11111111111111111111111111111111-2222222222222222-01";

    [Theory]
    [InlineData("incorrect_or_misleading")]
    [InlineData("incomplete")]
    [InlineData("outdated")]
    [InlineData("unclear")]
    [InlineData("truncated")]
    [InlineData("other")]
    public void AcceptsStructuredNegativeReasons(string reason)
    {
        Assert.True(FeedbackReason.TryNormalize(1, reason, out var normalized));
        Assert.Equal(reason, normalized);
    }

    [Fact]
    public void RequiresKnownReasonForNegativeFeedback()
    {
        Assert.False(FeedbackReason.TryNormalize(1, null, out _));
        Assert.False(FeedbackReason.TryNormalize(2, "unknown", out _));
    }

    [Fact]
    public void PositiveFeedbackUsesHelpfulReason()
    {
        Assert.True(FeedbackReason.TryNormalize(5, null, out var normalized));
        Assert.Equal(FeedbackReason.Helpful, normalized);
        Assert.False(FeedbackReason.TryNormalize(5, "other", out _));
    }

    [Fact]
    public void CorrelationRetainsPrivateRetrievalHandlesAndContentHashes()
    {
        var store = CreateCorrelationStore();
        var token = store.Save(
            TraceParent,
            "resp_test",
            "user-key",
            "chat-key",
            "question",
            "answer");

        var correlation = Assert.IsType<FeedbackCorrelation>(store.Consume(token));

        Assert.Equal("resp_test", correlation.ResponseId);
        Assert.Equal("user-key", correlation.UserIsolationKey);
        Assert.Equal("chat-key", correlation.ChatIsolationKey);
        Assert.Equal(GuideIdentity.Hash("question"), correlation.InputSha256);
        Assert.Equal(GuideIdentity.Hash("answer"), correlation.DisplayedTextSha256);
    }

    [Fact]
    public async Task PersistsStructuredNegativeFeedback()
    {
        var correlationStore = CreateCorrelationStore();
        var token = correlationStore.Save(
            TraceParent,
            "resp_test",
            "user-key",
            "chat-key",
            "question",
            "answer");
        var records = new StubFeedbackRecordStore();

        var result = await GuideEndpoints.FeedbackAsync(
            new FeedbackRequest(token, 1, "incomplete"),
            correlationStore,
            records,
            Configuration(),
            NullLoggerFactory.Instance);

        Assert.Equal(StatusCodes.Status204NoContent, Assert.IsAssignableFrom<IStatusCodeHttpResult>(result).StatusCode);
        Assert.Equal("incomplete", Assert.IsType<FeedbackRecord>(records.Record).Reason);
        Assert.Equal(token, records.RequestedFeedbackId);
    }

    [Fact]
    public async Task PositiveFeedbackDoesNotRetainPrivateRetrievalHandles()
    {
        var correlationStore = CreateCorrelationStore();
        var token = correlationStore.Save(
            TraceParent,
            "resp_test",
            "user-key",
            "chat-key",
            "question",
            "answer");
        var records = new StubFeedbackRecordStore();

        var result = await GuideEndpoints.FeedbackAsync(
            new FeedbackRequest(token, 5, null),
            correlationStore,
            records,
            Configuration(),
            NullLoggerFactory.Instance);

        Assert.Equal(StatusCodes.Status204NoContent, Assert.IsAssignableFrom<IStatusCodeHttpResult>(result).StatusCode);
        Assert.Null(records.Record);
    }

    [Fact]
    public async Task RestoresCorrelationWhenDurableStorageFails()
    {
        var correlationStore = CreateCorrelationStore();
        var token = correlationStore.Save(
            TraceParent,
            "resp_test",
            "user-key",
            "chat-key",
            "question",
            "answer");

        await Assert.ThrowsAsync<RequestFailedException>(() =>
            GuideEndpoints.FeedbackAsync(
                new FeedbackRequest(token, 1, "other"),
                correlationStore,
                new StubFeedbackRecordStore(
                    new RequestFailedException(503, "storage unavailable")),
                Configuration(),
                NullLoggerFactory.Instance));

        Assert.NotNull(correlationStore.Consume(token));
    }

    private static FeedbackStore CreateCorrelationStore() =>
        new(NullLogger<FeedbackStore>.Instance);

    private static IConfiguration Configuration() =>
        new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["FOUNDRY_GUIDE_AGENT_NAME"] = "foundry-guide",
                ["FOUNDRY_GUIDE_AGENT_VERSION"] = "active",
            })
            .Build();

    private sealed class StubFeedbackRecordStore : IFeedbackRecordStore
    {
        private readonly RequestFailedException? _exception;

        internal StubFeedbackRecordStore()
        {
        }

        internal StubFeedbackRecordStore(RequestFailedException exception)
        {
            _exception = exception;
        }

        internal FeedbackRecord? Record { get; private set; }

        internal string? RequestedFeedbackId { get; private set; }

        public Task SaveAsync(
            string feedbackId,
            FeedbackRecord record)
        {
            RequestedFeedbackId = feedbackId;
            Record = record;
            return _exception is null
                ? Task.CompletedTask
                : Task.FromException(_exception);
        }
    }
}
