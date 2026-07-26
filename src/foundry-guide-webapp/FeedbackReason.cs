internal static class FeedbackReason
{
    internal const string Helpful = "helpful";

    internal static bool TryNormalize(int rating, string? reason, out string normalized)
    {
        if (rating > 2)
        {
            normalized = Helpful;
            return string.IsNullOrWhiteSpace(reason);
        }

        normalized = reason?.Trim().ToLowerInvariant() ?? string.Empty;
        return normalized is
            "incorrect_or_misleading"
            or "incomplete"
            or "outdated"
            or "unclear"
            or "truncated"
            or "other";
    }
}
