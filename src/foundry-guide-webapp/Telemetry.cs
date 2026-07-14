using System.Diagnostics;

internal static class Telemetry
{
    internal const string ActivitySourceName = "MicrosoftFoundry.FoundryGuideWeb";
    internal const string FeedbackEventName = "foundry_guide.feedback";
    internal static readonly ActivitySource ActivitySource = new(ActivitySourceName);
}
