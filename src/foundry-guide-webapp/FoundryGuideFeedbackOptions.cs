internal sealed record FoundryGuideFeedbackOptions(
    Uri TableEndpoint,
    string TableName,
    TimeSpan Retention)
{
    private const int MaximumRetentionDays = 30;

    internal static FoundryGuideFeedbackOptions FromConfiguration(
        IConfiguration configuration)
    {
        var endpointValue = Require(
            configuration["FOUNDRY_GUIDE_FEEDBACK_TABLE_ENDPOINT"],
            "FOUNDRY_GUIDE_FEEDBACK_TABLE_ENDPOINT");
        if (!Uri.TryCreate(endpointValue, UriKind.Absolute, out var endpoint))
        {
            throw new InvalidOperationException(
                "FOUNDRY_GUIDE_FEEDBACK_TABLE_ENDPOINT must be an absolute URI.");
        }

        var retentionDays = configuration.GetValue(
            "FOUNDRY_GUIDE_FEEDBACK_RETENTION_DAYS",
            MaximumRetentionDays);
        if (retentionDays is < 1 or > MaximumRetentionDays)
        {
            throw new InvalidOperationException(
                $"FOUNDRY_GUIDE_FEEDBACK_RETENTION_DAYS must be between 1 and {MaximumRetentionDays}.");
        }

        return new FoundryGuideFeedbackOptions(
            endpoint,
            configuration["FOUNDRY_GUIDE_FEEDBACK_TABLE_NAME"] ?? "FoundryGuideFeedback",
            TimeSpan.FromDays(retentionDays));
    }

    private static string Require(string? value, string name) =>
        string.IsNullOrWhiteSpace(value)
            ? throw new InvalidOperationException($"{name} is required.")
            : value;
}
