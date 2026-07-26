internal static class FeedbackReason
{
    internal const string Helpful = "helpful";

    private static readonly HashSet<string> NegativeReasons =
    [
        "incorrect_or_misleading",
        "incomplete",
        "outdated",
        "unclear",
        "truncated",
        "other",
    ];

    internal static bool TryNormalize(int rating, string? reason, out string normalized)
    {
        if (rating > 2)
        {
            normalized = Helpful;
            return string.IsNullOrWhiteSpace(reason);
        }

        normalized = reason?.Trim().ToLowerInvariant() ?? string.Empty;
        return NegativeReasons.Contains(normalized);
    }
}
