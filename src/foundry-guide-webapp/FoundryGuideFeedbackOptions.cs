internal sealed record FoundryGuideFeedbackOptions(TimeSpan Retention)
{
    private const int MaximumRetentionDays = 30;

    internal static FoundryGuideFeedbackOptions FromConfiguration(
        IConfiguration configuration)
    {
        var retentionDays = configuration.GetValue(
            "FOUNDRY_GUIDE_FEEDBACK_RETENTION_DAYS",
            MaximumRetentionDays);
        if (retentionDays is < 1 or > MaximumRetentionDays)
        {
            throw new InvalidOperationException(
                $"FOUNDRY_GUIDE_FEEDBACK_RETENTION_DAYS must be between 1 and {MaximumRetentionDays}.");
        }

        return new FoundryGuideFeedbackOptions(TimeSpan.FromDays(retentionDays));
    }
}
