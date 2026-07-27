using System.Diagnostics;
using Azure.Monitor.OpenTelemetry.AspNetCore;

internal static class Telemetry
{
    internal const string ActivitySourceName = "MicrosoftFoundry.FoundryGuideWeb";
    internal const string FeedbackEventName = "foundry_guide.feedback";
    internal static readonly ActivitySource ActivitySource = new(ActivitySourceName);

    internal static void ConfigureAzureMonitor(AzureMonitorOptions options)
    {
        options.SamplingRatio = 1.0F;
        options.TracesPerSecond = null;
    }
}
