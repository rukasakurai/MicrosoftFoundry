using System.Diagnostics;
using Azure.Core;
using Azure.Core.Diagnostics;
using Azure.Identity;
using Azure.Monitor.OpenTelemetry.Exporter;
using Microsoft.Extensions.Logging;
using OpenTelemetry;
using OpenTelemetry.Logs;
using OpenTelemetry.Trace;

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

using var activitySource = new ActivitySource(
    FoundryGuideFeedbackTelemetry.ActivitySourceName);
using var loggerFactory = LoggerFactory.Create(builder =>
{
    builder.AddOpenTelemetry(logging =>
    {
        logging.SetResourceBuilder(
            FoundryGuideFeedbackTelemetry.CreateResourceBuilder());
        logging.AddAzureMonitorLogExporter(options =>
            FoundryGuideFeedbackTelemetry.ConfigureLogExporter(
                options,
                connectionString));
    });
});
var logger = loggerFactory.CreateLogger(
    FoundryGuideFeedbackTelemetry.ActivitySourceName);

var tracerProvider = Sdk.CreateTracerProviderBuilder()
    .SetResourceBuilder(FoundryGuideFeedbackTelemetry.CreateResourceBuilder())
    .AddSource(FoundryGuideFeedbackTelemetry.ActivitySourceName)
    .SetSampler(new AlwaysOnSampler())
    .AddAzureMonitorTraceExporter(options =>
        FoundryGuideFeedbackTelemetry.ConfigureTraceExporter(
            options,
            connectionString))
    .Build();

using var activity = FoundryGuideFeedbackTelemetry.StartInteraction(
    activitySource,
    agentName,
    agentVersion);

var credential = new AzureCliCredential();
var token = await credential.GetTokenAsync(
    FoundryGuideFeedbackProtocol.TokenContext,
    CancellationToken.None);

using var httpClient = new HttpClient();
FoundryGuideFeedbackProtocol.ConfigureAuthorization(httpClient, token);

var endpoint = projectEndpoint.TrimEnd('/');
var conversationId =
    await FoundryGuideFeedbackProtocol.CreateConversationAsync(
        httpClient,
        endpoint,
        prompt);

using var responseJson =
    await FoundryGuideFeedbackProtocol.CreateAgentResponseAsync(
        httpClient,
        endpoint,
        conversationId,
        agentName,
        agentVersion);
var responseText =
    FoundryGuideFeedbackProtocol.ExtractResponseText(responseJson);

Console.WriteLine();
Console.WriteLine(responseText);
Console.WriteLine();

var rating = options.Rating ?? ReadRating();
var result = rating <= 2 ? "negative" : "positive";

FoundryGuideFeedbackTelemetry.RecordFeedback(
    logger,
    rating,
    result,
    agentName,
    agentVersion);

activity?.Stop();

Console.WriteLine($"Recorded {result} feedback ({rating}/5).");
if (!tracerProvider.ForceFlush(30000))
{
    Console.Error.WriteLine("Warning: OpenTelemetry flush did not complete before timeout.");
}

tracerProvider.Dispose();

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
