internal sealed record WebAuthOptions(string TenantId, string ClientId)
{
    internal const string PolicyName = "foundry-guide-user";
    internal const string ScopeName = "access_as_user";

    internal string Audience => ClientId;
    internal string Scope => $"api://{ClientId}/{ScopeName}";

    internal static WebAuthOptions FromConfiguration(IConfiguration configuration)
    {
        var tenantId = RequireGuid(configuration["AUTH_TENANT_ID"], "AUTH_TENANT_ID");
        var clientId = RequireGuid(configuration["AUTH_CLIENT_ID"], "AUTH_CLIENT_ID");
        return new WebAuthOptions(tenantId, clientId);
    }

    private static string RequireGuid(string? value, string name) =>
        Guid.TryParse(value, out _)
            ? value!
            : throw new InvalidOperationException($"{name} must be a GUID.");
}
