internal static class SubscriptionIdentity
{
    internal static bool TryGet(HttpContext context, out string subscriptionId)
    {
        subscriptionId = context.Request.Headers[TokenUsageOptions.SubscriptionHeaderName]
            .ToString()
            .Trim();

        return subscriptionId.Length is > 0 and <= 128
            && subscriptionId.All(character =>
                char.IsAsciiLetterOrDigit(character)
                || character is '-' or '_' or '.');
    }
}
