using FoundryGuide.Quota;

internal sealed record FoundryGuideQuotaOptions(
    long TokenQuota,
    int MaxOutputTokens,
    int SafetyPaddingTokens,
    int MaxReservationTokens,
    TimeSpan ReservationTtl,
    Uri TableEndpoint,
    string TableName)
{
    internal QuotaLedgerOptions LedgerOptions =>
        new(TokenQuota, ReservationTtl, IncludeHistory: false);

    internal static FoundryGuideQuotaOptions FromConfiguration(IConfiguration configuration)
    {
        var endpointValue = Require(
            configuration["FOUNDRY_GUIDE_TOKEN_USAGE_TABLE_ENDPOINT"],
            "FOUNDRY_GUIDE_TOKEN_USAGE_TABLE_ENDPOINT");
        if (!Uri.TryCreate(endpointValue, UriKind.Absolute, out var endpoint))
        {
            throw new InvalidOperationException(
                "FOUNDRY_GUIDE_TOKEN_USAGE_TABLE_ENDPOINT must be an absolute URI.");
        }

        var options = new FoundryGuideQuotaOptions(
            PositiveLong(configuration, "FOUNDRY_GUIDE_TOKEN_QUOTA", 100_000),
            PositiveInt(configuration, "FOUNDRY_GUIDE_MAX_OUTPUT_TOKENS", 1_024),
            PositiveInt(configuration, "FOUNDRY_GUIDE_SAFETY_PADDING_TOKENS", 2_048),
            PositiveInt(configuration, "FOUNDRY_GUIDE_MAX_RESERVATION_TOKENS", 50_000),
            TimeSpan.FromSeconds(
                PositiveInt(configuration, "FOUNDRY_GUIDE_RESERVATION_TTL_SECONDS", 180)),
            endpoint,
            configuration["FOUNDRY_GUIDE_TOKEN_USAGE_TABLE_NAME"] ?? "FoundryGuideUsage");

        if (options.MaxOutputTokens + options.SafetyPaddingTokens
            >= options.MaxReservationTokens)
        {
            throw new InvalidOperationException(
                "FOUNDRY_GUIDE_MAX_RESERVATION_TOKENS must exceed the maximum output "
                + "and safety padding.");
        }

        if (options.ReservationTtl <= TimeSpan.FromSeconds(70))
        {
            throw new InvalidOperationException(
                "FOUNDRY_GUIDE_RESERVATION_TTL_SECONDS must exceed the Foundry timeout "
                + "by more than 30 seconds.");
        }

        return options;
    }

    private static string Require(string? value, string name) =>
        string.IsNullOrWhiteSpace(value)
            ? throw new InvalidOperationException($"{name} is required.")
            : value;

    private static int PositiveInt(
        IConfiguration configuration,
        string name,
        int defaultValue)
    {
        var value = configuration.GetValue(name, defaultValue);
        return value > 0
            ? value
            : throw new InvalidOperationException($"{name} must be greater than zero.");
    }

    private static long PositiveLong(
        IConfiguration configuration,
        string name,
        long defaultValue)
    {
        var value = configuration.GetValue(name, defaultValue);
        return value > 0
            ? value
            : throw new InvalidOperationException($"{name} must be greater than zero.");
    }
}
