using System.Diagnostics;
using Azure.Monitor.OpenTelemetry.Exporter;
using Microsoft.Extensions.Logging;
using OpenTelemetry.Resources;

internal static class FoundryGuideFeedbackTelemetry
{
    internal const string ActivitySourceName =
        "MicrosoftFoundry.FoundryGuideFeedback";
    internal const string FeedbackEventName = "foundry_guide.feedback";

    internal static ResourceBuilder CreateResourceBuilder() =>
        ResourceBuilder.CreateDefault().AddService(
            serviceName: "foundry-guide-feedback",
            serviceVersion: "1.0.0");

    internal static void ConfigureLogExporter(
        AzureMonitorExporterOptions options,
        string connectionString) =>
        options.ConnectionString = connectionString;

    internal static void ConfigureTraceExporter(
        AzureMonitorExporterOptions options,
        string connectionString)
    {
        options.ConnectionString = connectionString;
        options.SamplingRatio = 1.0F;
        options.TracesPerSecond = null;
    }

    internal static Activity? StartInteraction(
        ActivitySource activitySource,
        string agentName,
        string agentVersion)
    {
        var activity = activitySource.StartActivity(
            "foundry-guide-interaction",
            ActivityKind.Client);
        activity?.SetTag("gen_ai.system", "microsoft_foundry");
        activity?.SetTag("gen_ai.operation.name", "agent_run");
        activity?.SetTag("gen_ai.agent.name", agentName);
        activity?.SetTag("gen_ai.agent.version", agentVersion);
        return activity;
    }

    internal static void RecordFeedback(
        ILogger logger,
        int rating,
        string outcome,
        string agentName,
        string agentVersion)
    {
        logger.LogInformation(
            "{microsoft.custom_event.name} {feedback.rating} {feedback.outcome} "
            + "{foundry_guide.agent.name} {foundry_guide.agent.version} "
            + "{feedback.schema.version}",
            FeedbackEventName,
            rating,
            outcome,
            agentName,
            agentVersion,
            1);
    }
}
