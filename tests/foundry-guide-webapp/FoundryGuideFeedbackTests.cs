using System.Diagnostics;
using System.Net;
using System.Text.Json;
using Azure.Core;
using Azure.Monitor.OpenTelemetry.Exporter;
using Microsoft.Extensions.Logging;
using Xunit;

public sealed class FoundryGuideFeedbackTests
{
    [Fact]
    public async Task UsesStableConversationAndAgentResponseContracts()
    {
        var handler = new SequenceHandler(
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent("""{"id":"conv_test"}"""),
            },
            new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(
                    """
                    {
                      "output": [{
                        "content": [
                          { "type": "output_text", "text": "First" },
                          { "type": "text", "text": "Second" }
                        ]
                      }]
                    }
                    """),
            });
        using var httpClient = new HttpClient(handler);
        FoundryGuideFeedbackProtocol.ConfigureAuthorization(
            httpClient,
            new AccessToken(
                "console-token",
                DateTimeOffset.UtcNow.AddMinutes(5)));
        const string endpoint =
            "https://contoso.services.ai.azure.com/api/projects/guide";

        var conversationId =
            await FoundryGuideFeedbackProtocol.CreateConversationAsync(
                httpClient,
                endpoint,
                "Synthetic prompt",
                TestContext.Current.CancellationToken);
        using var response =
            await FoundryGuideFeedbackProtocol.CreateAgentResponseAsync(
                httpClient,
                endpoint,
                conversationId,
                "foundry-guide",
                "7",
                TestContext.Current.CancellationToken);

        Assert.Equal("conv_test", conversationId);
        Assert.Equal(
            ["https://ai.azure.com/.default"],
            FoundryGuideFeedbackProtocol.TokenContext.Scopes);
        Assert.Equal(
            $"First{Environment.NewLine}Second",
            FoundryGuideFeedbackProtocol.ExtractResponseText(response));

        Assert.Collection(
            handler.Requests,
            conversation =>
            {
                Assert.Equal("Bearer", conversation.AuthorizationScheme);
                Assert.Equal(
                    "console-token",
                    conversation.AuthorizationParameter);
                Assert.Equal(
                    $"{endpoint}/conversations?api-version=v1",
                    conversation.Uri.ToString());
                using var body = JsonDocument.Parse(conversation.Body);
                var item = Assert.Single(
                    body.RootElement.GetProperty("items").EnumerateArray());
                Assert.Equal("message", item.GetProperty("type").GetString());
                Assert.Equal("user", item.GetProperty("role").GetString());
                Assert.Equal(
                    "Synthetic prompt",
                    item.GetProperty("content").GetString());
            },
            agentResponse =>
            {
                Assert.Equal("Bearer", agentResponse.AuthorizationScheme);
                Assert.Equal(
                    "console-token",
                    agentResponse.AuthorizationParameter);
                Assert.Equal(
                    $"{endpoint}/openai/v1/responses",
                    agentResponse.Uri.ToString());
                using var body = JsonDocument.Parse(agentResponse.Body);
                Assert.Equal(
                    "conv_test",
                    body.RootElement.GetProperty("conversation").GetString());
                var agent =
                    body.RootElement.GetProperty("agent_reference");
                Assert.Equal(
                    "agent_reference",
                    agent.GetProperty("type").GetString());
                Assert.Equal(
                    "foundry-guide",
                    agent.GetProperty("name").GetString());
                Assert.Equal("7", agent.GetProperty("version").GetString());
            });
    }

    [Fact]
    public async Task SurfacesProtocolFailureStatusAndBody()
    {
        var handler = new SequenceHandler(
            new HttpResponseMessage(HttpStatusCode.BadRequest)
            {
                Content = new StringContent(
                    """{"error":{"code":"InvalidRequest"}}"""),
                ReasonPhrase = "Bad Request",
            });

        var exception = await Assert.ThrowsAsync<InvalidOperationException>(() =>
            FoundryGuideFeedbackProtocol.CreateConversationAsync(
                new HttpClient(handler),
                "https://contoso.services.ai.azure.com/api/projects/guide",
                "Synthetic prompt",
                TestContext.Current.CancellationToken));

        Assert.Contains("HTTP 400 Bad Request", exception.Message);
        Assert.Contains("InvalidRequest", exception.Message);
    }

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
        Assert.Equal(activity.TraceId, logger.ContextAtLog?.TraceId);
        Assert.Equal(activity.SpanId, logger.ContextAtLog?.SpanId);

        var telemetry = string.Join(
            " ",
            activity.TagObjects.Select(tag => $"{tag.Key}={tag.Value}")
                .Concat(logger.Properties.Select(
                    property => $"{property.Key}={property.Value}")));
        Assert.DoesNotContain("prompt", telemetry, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("answer", telemetry, StringComparison.OrdinalIgnoreCase);
        Assert.DoesNotContain("isolation", telemetry, StringComparison.OrdinalIgnoreCase);
    }

    private sealed record CapturedRequest(
        Uri Uri,
        string Body,
        string? AuthorizationScheme,
        string? AuthorizationParameter);

    private sealed class SequenceHandler(
        params HttpResponseMessage[] responses) : HttpMessageHandler
    {
        private readonly Queue<HttpResponseMessage> _responses = new(responses);

        internal List<CapturedRequest> Requests { get; } = [];

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            Requests.Add(
                new CapturedRequest(
                    request.RequestUri
                        ?? throw new InvalidOperationException(
                            "Request URI was missing."),
                    await request.Content!.ReadAsStringAsync(cancellationToken),
                    request.Headers.Authorization?.Scheme,
                    request.Headers.Authorization?.Parameter));
            return _responses.Dequeue();
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
