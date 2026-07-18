using System.Security.Claims;
using System.Threading.RateLimiting;
using Azure.Core;
using Azure.Identity;
using Azure.Monitor.OpenTelemetry.AspNetCore;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.RateLimiting;
using OpenTelemetry.Trace;

var builder = WebApplication.CreateBuilder(args);
var auth = WebAuthOptions.FromConfiguration(builder.Configuration);

builder.Services.AddSingleton(auth);
builder.Services.AddSingleton<TokenCredential>(_ =>
    new DefaultAzureCredential(new DefaultAzureCredentialOptions
    {
        ManagedIdentityClientId = builder.Configuration["MANAGED_IDENTITY_CLIENT_ID"],
    }));
builder.Services.AddSingleton<FeedbackStore>();
builder.Services.AddHttpClient<FoundryGuideClient>(client =>
{
    client.Timeout = TimeSpan.FromSeconds(40);
});

builder.Services
    .AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.Authority = $"https://login.microsoftonline.com/{auth.TenantId}/v2.0";
        options.Audience = auth.Audience;
        options.MapInboundClaims = false;
        options.RequireHttpsMetadata = true;
    });

builder.Services.AddAuthorization(options =>
{
    options.AddPolicy(WebAuthOptions.PolicyName, policy =>
    {
        policy.RequireAuthenticatedUser();
        policy.RequireAssertion(context =>
            context.User.FindAll("scp")
                .SelectMany(claim => claim.Value.Split(' ', StringSplitOptions.RemoveEmptyEntries))
                .Contains(WebAuthOptions.ScopeName, StringComparer.Ordinal));
    });
});

builder.Services.AddRateLimiter(options =>
{
    options.RejectionStatusCode = StatusCodes.Status429TooManyRequests;
    options.AddPolicy("authenticated-user", context =>
    {
        var partition = context.User.FindFirstValue("oid")
            ?? context.User.FindFirstValue("sub")
            ?? context.Connection.RemoteIpAddress?.ToString()
            ?? "unknown";

        return RateLimitPartition.GetFixedWindowLimiter(
            partition,
            _ => new FixedWindowRateLimiterOptions
            {
                AutoReplenishment = true,
                PermitLimit = 20,
                QueueLimit = 0,
                Window = TimeSpan.FromMinutes(1),
            });
    });
});

var openTelemetry = builder.Services
    .AddOpenTelemetry()
    .WithTracing(tracing => tracing.AddSource(Telemetry.ActivitySourceName));

if (!string.IsNullOrWhiteSpace(builder.Configuration["APPLICATIONINSIGHTS_CONNECTION_STRING"]))
{
    openTelemetry.UseAzureMonitor(options =>
    {
        options.SamplingRatio = 1.0F;
        options.TracesPerSecond = null;
    });
}

var app = builder.Build();

app.Use(async (context, next) =>
{
    context.Response.Headers.ContentSecurityPolicy =
        "default-src 'self'; base-uri 'self'; connect-src 'self' https://login.microsoftonline.com; "
        + "form-action 'self' https://login.microsoftonline.com; frame-ancestors 'none'; "
        + "frame-src https://login.microsoftonline.com; img-src 'self'; object-src 'none'; "
        + "script-src 'self'; style-src 'self'";
    context.Response.Headers["Permissions-Policy"] = "camera=(), geolocation=(), microphone=()";
    context.Response.Headers["Referrer-Policy"] = "no-referrer";
    context.Response.Headers.XContentTypeOptions = "nosniff";
    await next();
});

app.UseDefaultFiles();
app.UseStaticFiles();
app.UseAuthentication();
app.UseAuthorization();
app.UseRateLimiter();

app.MapGet("/health", () => Results.Ok(new { status = "healthy" }));
app.MapGet("/api/config", (WebAuthOptions options) => Results.Ok(new
{
    authTenantId = options.TenantId,
    authClientId = options.ClientId,
    authScope = options.Scope,
}));

app.MapPost("/api/chat", GuideEndpoints.ChatAsync)
    .RequireAuthorization(WebAuthOptions.PolicyName)
    .RequireRateLimiting("authenticated-user");

app.MapPost("/api/feedback", GuideEndpoints.Feedback)
    .RequireAuthorization(WebAuthOptions.PolicyName)
    .RequireRateLimiting("authenticated-user");

app.MapFallbackToFile("index.html");

await app.RunAsync();
