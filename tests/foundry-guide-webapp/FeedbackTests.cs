using System.Diagnostics;
using Azure;
using Azure.Monitor.OpenTelemetry.AspNetCore;
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

    [Fact]
    public async Task EmitsCorrelatedContentFreeFeedbackTelemetry()
    {
        var stoppedActivities = new List<Activity>();
        using var listener = new ActivityListener
        {
            ShouldListenTo = source => source.Name == Telemetry.ActivitySourceName,
            Sample = (ref ActivityCreationOptions<ActivityContext> _) =>
                ActivitySamplingResult.AllDataAndRecorded,
            ActivityStopped = stoppedActivities.Add,
        };
        ActivitySource.AddActivityListener(listener);

        var correlationStore = CreateCorrelationStore();
        var token = correlationStore.Save(
            TraceParent,
            "resp_test",
            "user-key",
            "chat-key",
            "private question",
            "private answer");
        var loggerFactory = new CaptureLoggerFactory();

        var result = await GuideEndpoints.FeedbackAsync(
            new FeedbackRequest(token, 1, "incomplete"),
            correlationStore,
            new StubFeedbackRecordStore(),
            Configuration(),
            loggerFactory);

        Assert.Equal(
            StatusCodes.Status204NoContent,
            Assert.IsAssignableFrom<IStatusCodeHttpResult>(result).StatusCode);

        var activity = Assert.Single(stoppedActivities);
        Assert.Equal(
            ActivityTraceId.CreateFromString("11111111111111111111111111111111"),
            activity.TraceId);
        Assert.Equal("resp_test", activity.GetTagItem("foundry_guide.response.id"));
        Assert.Equal("incomplete", activity.GetTagItem("feedback.reason"));
        Assert.Equal(token, activity.GetTagItem("foundry_guide.feedback.id"));

        Assert.Equal(
            Telemetry.FeedbackEventName,
            loggerFactory.Logger.Properties["microsoft.custom_event.name"]);
        Assert.Equal(1, loggerFactory.Logger.Properties["feedback.rating"]);
        Assert.Equal("negative", loggerFactory.Logger.Properties["feedback.outcome"]);
        Assert.Equal("incomplete", loggerFactory.Logger.Properties["feedback.reason"]);
        Assert.Equal(
            "foundry-guide",
            loggerFactory.Logger.Properties["foundry_guide.agent.name"]);
        Assert.Equal(
            "active",
            loggerFactory.Logger.Properties["foundry_guide.agent.version"]);
        Assert.Equal("resp_test", loggerFactory.Logger.Properties["foundry_guide.response.id"]);
        Assert.Equal(token, loggerFactory.Logger.Properties["foundry_guide.feedback.id"]);
        Assert.Equal("web", loggerFactory.Logger.Properties["feedback.channel"]);
        Assert.Equal(2, loggerFactory.Logger.Properties["feedback.schema.version"]);
        Assert.Equal(activity.TraceId, loggerFactory.Logger.ContextAtLog?.TraceId);
        Assert.Equal(activity.SpanId, loggerFactory.Logger.ContextAtLog?.SpanId);

        var telemetry = string.Join(
            " ",
            activity.TagObjects.Select(tag => $"{tag.Key}={tag.Value}")
                .Concat(loggerFactory.Logger.Properties.Select(
                    property => $"{property.Key}={property.Value}")));
        Assert.DoesNotContain("private question", telemetry, StringComparison.Ordinal);
        Assert.DoesNotContain("private answer", telemetry, StringComparison.Ordinal);
        Assert.DoesNotContain("user-key", telemetry, StringComparison.Ordinal);
        Assert.DoesNotContain("chat-key", telemetry, StringComparison.Ordinal);
    }

    [Fact]
    public void FeedbackTelemetryIsNotSampled()
    {
        var options = new AzureMonitorOptions();

        Telemetry.ConfigureAzureMonitor(options);

        Assert.Equal(1.0F, options.SamplingRatio);
        Assert.Null(options.TracesPerSecond);
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

    private sealed class CaptureLoggerFactory : ILoggerFactory
    {
        internal CaptureLogger Logger { get; } = new();

        public void AddProvider(ILoggerProvider provider)
        {
        }

        public ILogger CreateLogger(string categoryName) => Logger;

        public void Dispose()
        {
        }
    }

    private sealed class CaptureLogger : ILogger
    {
        internal Dictionary<string, object?> Properties { get; } =
            new(StringComparer.Ordinal);

        internal ActivityContext? ContextAtLog { get; private set; }

        public IDisposable? BeginScope<TState>(TState state)
            where TState : notnull =>
            NullScope.Instance;

        public bool IsEnabled(LogLevel logLevel) => true;

        public void Log<TState>(
            LogLevel logLevel,
            EventId eventId,
            TState state,
            Exception? exception,
            Func<TState, Exception?, string> formatter)
        {
            ContextAtLog = Activity.Current?.Context;
            if (state is not IEnumerable<KeyValuePair<string, object?>> values)
            {
                return;
            }

            foreach (var value in values)
            {
                Properties[value.Key] = value.Value;
            }
        }
    }

    private sealed class NullScope : IDisposable
    {
        internal static readonly NullScope Instance = new();

        public void Dispose()
        {
        }
    }
}
