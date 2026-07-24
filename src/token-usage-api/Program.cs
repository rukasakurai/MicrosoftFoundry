using Azure.Core;
using Azure.Data.Tables;
using Azure.Identity;

var builder = WebApplication.CreateBuilder(args);
var options = TokenUsageOptions.FromConfiguration(builder.Configuration);

builder.Services.AddSingleton(options);
builder.Services.AddSingleton(options.LedgerOptions);
builder.Services.AddSingleton(TimeProvider.System);
builder.Services.AddSingleton<TokenCredential>(_ =>
    new DefaultAzureCredential(new DefaultAzureCredentialOptions
    {
        ManagedIdentityClientId = builder.Configuration["MANAGED_IDENTITY_CLIENT_ID"],
    }));
builder.Services.AddHttpClient("foundry", client => client.Timeout = options.BackendTimeout);
builder.Services.AddHttpClient("log-analytics", client =>
    client.Timeout = TimeSpan.FromSeconds(30));
builder.Services.AddSingleton<LogAnalyticsUsageReader>();
builder.Services.AddSingleton<FoundryChatProxy>();

if (options.UseInMemoryLedger)
{
    builder.Services.AddSingleton<IQuotaLedger, InMemoryQuotaLedger>();
}
else
{
    builder.Services.AddSingleton(serviceProvider =>
    {
        var credential = serviceProvider.GetRequiredService<TokenCredential>();
        var service = new TableServiceClient(options.StorageTableEndpoint, credential);
        return service.GetTableClient(options.StorageTableName);
    });
    builder.Services.AddSingleton<TableQuotaLedger>();
    builder.Services.AddSingleton<IQuotaLedger>(serviceProvider =>
        serviceProvider.GetRequiredService<TableQuotaLedger>());
    builder.Services.AddHostedService<TableReservationReaper>();
}

var app = builder.Build();

app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));

app.MapGet("/api/simple/usage", async (
    HttpContext context,
    LogAnalyticsUsageReader usageReader,
    CancellationToken cancellationToken) =>
{
    if (!SubscriptionIdentity.TryGet(context, out var subscriptionId))
    {
        return Results.Unauthorized();
    }

    var usage = await usageReader.GetUsageAsync(subscriptionId, cancellationToken);
    return Results.Ok(usage);
});

app.MapGet("/api/strict/usage", async (
    HttpContext context,
    IQuotaLedger ledger,
    CancellationToken cancellationToken) =>
{
    if (!SubscriptionIdentity.TryGet(context, out var subscriptionId))
    {
        return Results.Unauthorized();
    }

    var usage = await ledger.GetUsageAsync(subscriptionId, cancellationToken);
    FoundryChatProxy.ApplyQuotaHeaders(context.Response, usage, 0);
    return Results.Ok(usage);
});

app.MapPost("/api/strict/chat/completions", async (
    HttpContext context,
    FoundryChatProxy proxy) => await proxy.HandleAsync(context));

await app.RunAsync();
