internal sealed class TokenUsageOptions
{
    internal const string SubscriptionHeaderName = "X-APIM-Subscription-ID";

    public required Uri FoundryEndpoint { get; init; }

    public required string ModelDeploymentName { get; init; }

    public required string LogAnalyticsWorkspaceId { get; init; }

    public required long SimpleTokenQuota { get; init; }

    public required long StrictTokenQuota { get; init; }

    public required int StrictReservationTokens { get; init; }

    public required int StrictMaxOutputTokens { get; init; }

    public required int StrictSafetyPaddingTokens { get; init; }

    public required TimeSpan ReservationTtl { get; init; }

    public required TimeSpan BackendTimeout { get; init; }

    public required bool UseInMemoryLedger { get; init; }

    public Uri? StorageTableEndpoint { get; init; }

    public string StorageTableName { get; init; } = "TokenUsage";

    internal static TokenUsageOptions FromConfiguration(IConfiguration configuration)
    {
        var foundryEndpoint = RequiredUri(configuration, "FOUNDRY_INFERENCE_ENDPOINT");
        var workspaceId = Required(configuration, "LOG_ANALYTICS_WORKSPACE_ID");
        var modelDeploymentName = Required(configuration, "MODEL_DEPLOYMENT_NAME");
        var useInMemoryLedger = configuration.GetValue("TOKEN_USAGE_USE_IN_MEMORY_LEDGER", false);
        var storageTableEndpointValue = configuration["TOKEN_USAGE_TABLE_ENDPOINT"];

        if (!useInMemoryLedger && string.IsNullOrWhiteSpace(storageTableEndpointValue))
        {
            throw new InvalidOperationException(
                "TOKEN_USAGE_TABLE_ENDPOINT is required unless TOKEN_USAGE_USE_IN_MEMORY_LEDGER is true.");
        }

        var options = new TokenUsageOptions
        {
            FoundryEndpoint = foundryEndpoint,
            ModelDeploymentName = modelDeploymentName,
            LogAnalyticsWorkspaceId = workspaceId,
            SimpleTokenQuota = PositiveLong(configuration, "SIMPLE_TOKEN_QUOTA", 10_000),
            StrictTokenQuota = PositiveLong(configuration, "STRICT_TOKEN_QUOTA", 10_000),
            StrictReservationTokens = PositiveInt(configuration, "STRICT_RESERVATION_TOKENS", 1_024),
            StrictMaxOutputTokens = PositiveInt(configuration, "STRICT_MAX_OUTPUT_TOKENS", 256),
            StrictSafetyPaddingTokens = PositiveInt(configuration, "STRICT_SAFETY_PADDING_TOKENS", 256),
            ReservationTtl = TimeSpan.FromSeconds(
                PositiveInt(configuration, "STRICT_RESERVATION_TTL_SECONDS", 180)),
            BackendTimeout = TimeSpan.FromSeconds(
                PositiveInt(configuration, "FOUNDRY_BACKEND_TIMEOUT_SECONDS", 90)),
            UseInMemoryLedger = useInMemoryLedger,
            StorageTableEndpoint = string.IsNullOrWhiteSpace(storageTableEndpointValue)
                ? null
                : new Uri(storageTableEndpointValue, UriKind.Absolute),
            StorageTableName = configuration["TOKEN_USAGE_TABLE_NAME"] ?? "TokenUsage",
        };

        if (options.StrictMaxOutputTokens + options.StrictSafetyPaddingTokens
            >= options.StrictReservationTokens)
        {
            throw new InvalidOperationException(
                "STRICT_RESERVATION_TOKENS must exceed STRICT_MAX_OUTPUT_TOKENS plus "
                + "STRICT_SAFETY_PADDING_TOKENS.");
        }

        if (options.ReservationTtl <= options.BackendTimeout.Add(TimeSpan.FromSeconds(30)))
        {
            throw new InvalidOperationException(
                "STRICT_RESERVATION_TTL_SECONDS must exceed "
                + "FOUNDRY_BACKEND_TIMEOUT_SECONDS by more than 30 seconds.");
        }

        return options;
    }

    private static string Required(IConfiguration configuration, string name)
    {
        var value = configuration[name];
        return !string.IsNullOrWhiteSpace(value)
            ? value
            : throw new InvalidOperationException($"{name} is required.");
    }

    private static Uri RequiredUri(IConfiguration configuration, string name)
    {
        var value = Required(configuration, name);
        return Uri.TryCreate(value, UriKind.Absolute, out var uri)
            ? uri
            : throw new InvalidOperationException($"{name} must be an absolute URI.");
    }

    private static int PositiveInt(IConfiguration configuration, string name, int defaultValue)
    {
        var value = configuration.GetValue(name, defaultValue);
        return value > 0
            ? value
            : throw new InvalidOperationException($"{name} must be greater than zero.");
    }

    private static long PositiveLong(IConfiguration configuration, string name, long defaultValue)
    {
        var value = configuration.GetValue(name, defaultValue);
        return value > 0
            ? value
            : throw new InvalidOperationException($"{name} must be greater than zero.");
    }
}
