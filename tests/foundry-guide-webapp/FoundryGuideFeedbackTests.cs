using System.Diagnostics;
using Azure.Monitor.OpenTelemetry.Exporter;
using Microsoft.Extensions.Logging;
using Xunit;

public sealed class FoundryGuideFeedbackTests
{
    [Fact]
    public void EmitsContentFreeUnsampledTelemetry()
    {
        var options = new AzureMonitorExporterOptions();
        FoundryGuideFeedbackTelemetry.ConfigureTraceExporter(
            options,
            "InstrumentationKey=00000000-0000-0000-0000-000000000000");

        Assert.Equal(1.0F, options.SamplingRatio);
        Assert.Null(options.TracesPerSecond);

        var stoppedActivities = new List<Activity>();
        using var listener = new ActivityListener
        {
            ShouldListenTo = source =>
                source.Name == FoundryGuideFeedbackTelemetry.ActivitySourceName,
            Sample = (ref ActivityCreationOptions<ActivityContext> _) =>
                ActivitySamplingResult.AllDataAndRecorded,
            ActivityStopped = stoppedActivities.Add,
        };
        ActivitySource.AddActivityListener(listener);

        var logger = new CaptureLogger();
        using var source =
            new ActivitySource(FoundryGuideFeedbackTelemetry.ActivitySourceName);
        using (var interaction = FoundryGuideFeedbackTelemetry.StartInteraction(
                   source,
                   "foundry-guide",
                   "7"))
        {
            Assert.NotNull(interaction);
            FoundryGuideFeedbackTelemetry.RecordFeedback(
                logger,
                1,
                "negative",
                "foundry-guide",
                "7");
        }

        var activity = Assert.Single(stoppedActivities);
        Assert.Equal("microsoft_foundry", activity.GetTagItem("gen_ai.system"));
        Assert.Equal("agent_run", activity.GetTagItem("gen_ai.operation.name"));
        Assert.Equal("foundry-guide", activity.GetTagItem("gen_ai.agent.name"));
        Assert.Equal("7", activity.GetTagItem("gen_ai.agent.version"));

        Assert.Equal(
            FoundryGuideFeedbackTelemetry.FeedbackEventName,
            logger.Properties["microsoft.custom_event.name"]);
        Assert.Equal(1, logger.Properties["feedback.rating"]);
        Assert.Equal("negative", logger.Properties["feedback.outcome"]);
        Assert.Equal(
            "foundry-guide",
            logger.Properties["foundry_guide.agent.name"]);
        Assert.Equal(
            "7",
            logger.Properties["foundry_guide.agent.version"]);
        Assert.Equal(1, logger.Properties["feedback.schema.version"]);
        var telemetry = string.Join(
            " ",
            activity.TagObjects.Select(tag => $"{tag.Key}={tag.Value}")
                .Concat(logger.Properties.Select(
                    property => $"{property.Key}={property.Value}")));
        Assert.DoesNotContain("prompt", telemetry, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("answer", telemetry, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("isolation", telemetry, StringComparison.OrdinalIgnoreCase);
    }

    private sealed class CaptureLogger : ILogger
    {
        internal Dictionary<string, object?> Properties { get; } =
            new(StringComparer.Ordinal);

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
