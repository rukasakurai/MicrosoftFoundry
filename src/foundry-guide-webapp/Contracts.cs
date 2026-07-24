internal sealed record ChatRequest(string? Input, string? PreviousResponseId, string? ChatId);

internal sealed record ChatResponse(
    string ResponseId,
    string ChatId,
    string Text,
    string FeedbackToken,
    GuideUsage Usage);

internal sealed record GuideUsage(
    long Limit,
    long Used,
    long Reserved,
    long Remaining,
    DateTimeOffset PeriodStart,
    DateTimeOffset PeriodEnd,
    DateTimeOffset ObservedAt,
    string Consistency)
{
    internal static GuideUsage From(UsageSnapshot usage) =>
        new(
            usage.Limit,
            usage.Used,
            usage.Reserved,
            usage.Remaining,
            usage.PeriodStart,
            usage.PeriodEnd,
            usage.ObservedAt,
            usage.Consistency);
}

internal sealed record FeedbackRequest(string? FeedbackToken, int Rating);

internal sealed record ErrorResponse(
    string Error,
    string? Code = null,
    GuideUsage? Usage = null);
