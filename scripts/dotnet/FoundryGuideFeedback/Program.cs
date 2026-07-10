using System.Diagnostics;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using Azure.Core;
using Azure.Core.Diagnostics;
using Azure.Identity;
using Azure.Monitor.OpenTelemetry.Exporter;
using OpenTelemetry;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

const string ActivitySourceName = "MicrosoftFoundry.FoundryGuideFeedback";

var options = CliOptions.Parse(args);
var projectEndpoint = Require(options.ProjectEndpoint ?? Environment.GetEnvironmentVariable("PROJECT_ENDPOINT"), "PROJECT_ENDPOINT");
var agentName = options.AgentName ?? Environment.GetEnvironmentVariable("FOUNDRY_GUIDE_AGENT_NAME") ?? "foundry-guide";
var agentVersion = options.AgentVersion ?? Environment.GetEnvironmentVariable("FOUNDRY_GUIDE_AGENT_VERSION") ?? "1";
var connectionString =
    options.ApplicationInsightsConnectionString
    ?? Environment.GetEnvironmentVariable("APPLICATIONINSIGHTS_CONNECTION_STRING")
    ?? Environment.GetEnvironmentVariable("APPLICATION_INSIGHTS_CONNECTION_STRING");

if (string.IsNullOrWhiteSpace(connectionString))
{
    throw new InvalidOperationException("APPLICATIONINSIGHTS_CONNECTION_STRING is required to emit feedback telemetry.");
}

var prompt = options.Prompt;
if (string.IsNullOrWhiteSpace(prompt))
{
    Console.Write("Ask Foundry Guide: ");
    prompt = Console.ReadLine();
}

if (string.IsNullOrWhiteSpace(prompt))
{
    throw new InvalidOperationException("A non-empty prompt is required.");
}

using var azureDiagnostics = IsTrue(Environment.GetEnvironmentVariable("FOUNDRY_GUIDE_OTEL_DIAGNOSTICS"))
    ? AzureEventSourceListener.CreateConsoleLogger()
    : null;

using var activitySource = new ActivitySource(ActivitySourceName);
var tracerProvider = Sdk.CreateTracerProviderBuilder()
    .SetResourceBuilder(ResourceBuilder.CreateDefault().AddService(
        serviceName: "foundry-guide-feedback",
        serviceVersion: "1.0.0"))
    .AddSource(ActivitySourceName)
    .SetSampler(new AlwaysOnSampler())
    .AddAzureMonitorTraceExporter(o =>
    {
        o.ConnectionString = connectionString;
        o.SamplingRatio = 1.0F;
        o.TracesPerSecond = null;
    })
    .Build();

using var activity = activitySource.StartActivity("foundry-guide-interaction", ActivityKind.Client);
activity?.SetTag("gen_ai.system", "microsoft_foundry");
activity?.SetTag("gen_ai.operation.name", "agent_run");
activity?.SetTag("gen_ai.agent.name", agentName);
activity?.SetTag("gen_ai.agent.version", agentVersion);

var credential = new AzureCliCredential();
var token = await credential.GetTokenAsync(
    new TokenRequestContext(["https://ai.azure.com/.default"]),
    CancellationToken.None);

using var httpClient = new HttpClient();
httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);

var endpoint = projectEndpoint.TrimEnd('/');
var conversationId = await CreateConversationAsync(httpClient, endpoint, prompt);

var responseJson = await CreateAgentResponseAsync(httpClient, endpoint, conversationId, agentName, agentVersion);
var responseText = ExtractResponseText(responseJson);

Console.WriteLine();
Console.WriteLine(responseText);
Console.WriteLine();

var rating = options.Rating ?? ReadRating();
var result = rating <= 2 ? "negative" : "positive";

activity?.SetTag("gen_ai.evaluation.name", "user_feedback");
activity?.SetTag("gen_ai.evaluation.score", rating);
activity?.SetTag("gen_ai.evaluation.result", result);
activity?.AddEvent(new ActivityEvent(
    "gen_ai.evaluation.result",
    tags: new ActivityTagsCollection
    {
        ["gen_ai.agent.name"] = agentName,
        ["gen_ai.agent.version"] = agentVersion,
        ["gen_ai.evaluation.name"] = "user_feedback",
        ["gen_ai.evaluation.scale"] = "five_point",
        ["gen_ai.evaluation.score"] = rating,
        ["gen_ai.evaluation.result"] = result
    }));

using var feedbackActivity = activitySource.StartActivity("gen_ai.evaluation.result", ActivityKind.Internal);
feedbackActivity?.SetTag("gen_ai.system", "microsoft_foundry");
feedbackActivity?.SetTag("gen_ai.agent.name", agentName);
feedbackActivity?.SetTag("gen_ai.agent.version", agentVersion);
feedbackActivity?.SetTag("gen_ai.evaluation.name", "user_feedback");
feedbackActivity?.SetTag("gen_ai.evaluation.scale", "five_point");
feedbackActivity?.SetTag("gen_ai.evaluation.score", rating);
feedbackActivity?.SetTag("gen_ai.evaluation.result", result);
feedbackActivity?.Stop();
activity?.Stop();

Console.WriteLine($"Recorded {result} feedback ({rating}/5).");
if (!tracerProvider.ForceFlush(30000))
{
    Console.Error.WriteLine("Warning: OpenTelemetry flush did not complete before timeout.");
}

tracerProvider.Dispose();

static async Task<string> CreateConversationAsync(HttpClient httpClient, string endpoint, string prompt)
{
    var body = JsonSerializer.Serialize(new
    {
        items = new[]
        {
            new
            {
                type = "message",
                role = "user",
                content = prompt
            }
        }
    });

    using var response = await httpClient.PostAsync(
        $"{endpoint}/conversations?api-version=v1",
        new StringContent(body, Encoding.UTF8, "application/json"));

    var content = await response.Content.ReadAsStringAsync();
    EnsureSuccess(response, content, "create conversation");

    using var document = JsonDocument.Parse(content);
    if (document.RootElement.TryGetProperty("id", out var id))
    {
        return id.GetString() ?? throw new InvalidOperationException("Conversation id was empty.");
    }

    throw new InvalidOperationException("Conversation response did not include an id.");
}

static async Task<JsonDocument> CreateAgentResponseAsync(
    HttpClient httpClient,
    string endpoint,
    string conversationId,
    string agentName,
    string agentVersion)
{
    var body = JsonSerializer.Serialize(new
    {
        conversation = conversationId,
        agent_reference = new
        {
            type = "agent_reference",
            name = agentName,
            version = agentVersion
        }
    });

    using var response = await httpClient.PostAsync(
        $"{endpoint}/openai/v1/responses",
        new StringContent(body, Encoding.UTF8, "application/json"));

    var content = await response.Content.ReadAsStringAsync();
    EnsureSuccess(response, content, "create agent response");
    return JsonDocument.Parse(content);
}

static string ExtractResponseText(JsonDocument document)
{
    if (document.RootElement.TryGetProperty("output_text", out var outputText)
        && outputText.ValueKind == JsonValueKind.String)
    {
        return outputText.GetString() ?? string.Empty;
    }

    var texts = new List<string>();
    CollectMessageText(document.RootElement, texts);
    return texts.Count > 0
        ? string.Join(Environment.NewLine, texts.Distinct())
        : document.RootElement.GetRawText();
}

static void CollectMessageText(JsonElement element, List<string> texts)
{
    if (element.ValueKind == JsonValueKind.Object)
    {
        if (element.TryGetProperty("type", out var type)
            && type.GetString() is "output_text" or "text"
            && element.TryGetProperty("text", out var text)
            && text.ValueKind == JsonValueKind.String)
        {
            var value = text.GetString();
            if (!string.IsNullOrWhiteSpace(value))
            {
                texts.Add(value);
            }
        }

        foreach (var property in element.EnumerateObject())
        {
            CollectMessageText(property.Value, texts);
        }
    }
    else if (element.ValueKind == JsonValueKind.Array)
    {
        foreach (var item in element.EnumerateArray())
        {
            CollectMessageText(item, texts);
        }
    }
}

static int ReadRating()
{
    while (true)
    {
        Console.Write("Rate this answer from 1 (bad) to 5 (good): ");
        var input = Console.ReadLine();
        if (int.TryParse(input, out var rating) && rating is >= 1 and <= 5)
        {
            return rating;
        }

        Console.WriteLine("Enter a number from 1 to 5.");
    }
}

static void EnsureSuccess(HttpResponseMessage response, string content, string action)
{
    if (response.IsSuccessStatusCode)
    {
        return;
    }

    throw new InvalidOperationException(
        $"Failed to {action}. HTTP {(int)response.StatusCode} {response.ReasonPhrase}: {content}");
}

static string Require(string? value, string name)
{
    if (string.IsNullOrWhiteSpace(value))
    {
        throw new InvalidOperationException($"{name} is required.");
    }

    return value;
}

static bool IsTrue(string? value) =>
    value?.Equals("true", StringComparison.OrdinalIgnoreCase) == true
    || value == "1"
    || value?.Equals("yes", StringComparison.OrdinalIgnoreCase) == true;

sealed record CliOptions(
    string? ProjectEndpoint,
    string? AgentName,
    string? AgentVersion,
    string? Prompt,
    int? Rating,
    string? ApplicationInsightsConnectionString)
{
    public static CliOptions Parse(string[] args)
    {
        string? projectEndpoint = null;
        string? agentName = null;
        string? agentVersion = null;
        string? prompt = null;
        int? rating = null;
        string? connectionString = null;

        for (var i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--project-endpoint" or "-e":
                    projectEndpoint = ReadValue(args, ref i);
                    break;
                case "--agent-name" or "-n":
                    agentName = ReadValue(args, ref i);
                    break;
                case "--agent-version" or "-v":
                    agentVersion = ReadValue(args, ref i);
                    break;
                case "--prompt" or "-p":
                    prompt = ReadValue(args, ref i);
                    break;
                case "--rating" or "-r":
                    rating = int.Parse(ReadValue(args, ref i));
                    if (rating is < 1 or > 5)
                    {
                        throw new ArgumentOutOfRangeException(nameof(rating), "Rating must be between 1 and 5.");
                    }
                    break;
                case "--application-insights-connection-string":
                    connectionString = ReadValue(args, ref i);
                    break;
                case "--help" or "-h":
                    PrintUsage();
                    Environment.Exit(0);
                    break;
                default:
                    throw new ArgumentException($"Unknown option: {args[i]}");
            }
        }

        return new CliOptions(projectEndpoint, agentName, agentVersion, prompt, rating, connectionString);
    }

    static string ReadValue(string[] args, ref int index)
    {
        if (index + 1 >= args.Length)
        {
            throw new ArgumentException($"Missing value for {args[index]}.");
        }

        return args[++index];
    }

    static void PrintUsage()
    {
        Console.WriteLine("Usage: FoundryGuideFeedback [OPTIONS]");
        Console.WriteLine();
        Console.WriteLine("Options:");
        Console.WriteLine("  --project-endpoint, -e <url>");
        Console.WriteLine("  --agent-name, -n <name>");
        Console.WriteLine("  --agent-version, -v <version>");
        Console.WriteLine("  --prompt, -p <text>");
        Console.WriteLine("  --rating, -r <1-5>");
        Console.WriteLine("  --application-insights-connection-string <connection-string>");
    }
}
