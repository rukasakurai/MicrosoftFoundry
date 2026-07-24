using System.Net;
using System.Security.Claims;
using System.Text.Json;
using Azure.Core;
using Microsoft.Extensions.Configuration;
using Xunit;

public sealed class FoundryGuideClientTests
{
    [Fact]
    public async Task ParsesExactUsageAndBoundsOutput()
    {
        var handler = new StubHandler(
            """
            {
              "id": "resp_test",
              "output_text": "OK",
              "usage": {
                "input_tokens": 145,
                "output_tokens": 5,
                "total_tokens": 150
              }
            }
            """);
        var client = CreateClient(handler);

        var response = await client.SendAsync(
            "Hello",
            null,
            "subject",
            Guid.NewGuid().ToString("N"),
            TestContext.Current.CancellationToken);

        Assert.Equal(new FoundryTokenUsage(145, 5, 150), response.Usage);
        using var payload = JsonDocument.Parse(Assert.IsType<string>(handler.RequestBody));
        Assert.Equal(128, payload.RootElement.GetProperty("max_output_tokens").GetInt32());
        Assert.False(payload.RootElement.GetProperty("stream").GetBoolean());
        Assert.Equal("subject", handler.UserIsolationKey);
    }

    [Fact]
    public async Task RejectsInconsistentUsage()
    {
        var client = CreateClient(
            new StubHandler(
                """
                {
                  "id": "resp_test",
                  "output_text": "OK",
                  "usage": {
                    "input_tokens": 145,
                    "output_tokens": 5,
                    "total_tokens": 149
                  }
                }
                """));

        await Assert.ThrowsAsync<InvalidDataException>(() => client.SendAsync(
            "Hello",
            null,
            "subject",
            Guid.NewGuid().ToString("N"),
            TestContext.Current.CancellationToken));
    }

    [Fact]
    public async Task RejectsResponseWithoutIdAsInvalidData()
    {
        var client = CreateClient(
            new StubHandler(
                """
                {
                  "output_text": "OK",
                  "usage": {
                    "input_tokens": 145,
                    "output_tokens": 5,
                    "total_tokens": 150
                  }
                }
                """));

        await Assert.ThrowsAsync<InvalidDataException>(() => client.SendAsync(
            "Hello",
            null,
            "subject",
            Guid.NewGuid().ToString("N"),
            TestContext.Current.CancellationToken));
    }

    [Fact]
    public void QuotaSubjectIncludesTenant()
    {
        var first = Principal("tenant-a", "user");
        var second = Principal("tenant-b", "user");

        Assert.True(GuideIdentity.TryGetSubject(first, out var firstSubject));
        Assert.True(GuideIdentity.TryGetSubject(second, out var secondSubject));
        Assert.NotEqual(firstSubject, secondSubject);
        Assert.Equal(64, firstSubject.Length);
    }

    private static FoundryGuideClient CreateClient(StubHandler handler)
    {
        var configuration = new ConfigurationBuilder()
            .AddInMemoryCollection(new Dictionary<string, string?>
            {
                ["PROJECT_ENDPOINT"] = "https://contoso.services.ai.azure.com/api/projects/guide",
                ["FOUNDRY_GUIDE_AGENT_NAME"] = "foundry-guide",
            })
            .Build();
        var options = new FoundryGuideQuotaOptions(
            1_000,
            128,
            128,
            512,
            TimeSpan.FromMinutes(3),
            new Uri("https://contoso.table.core.windows.net"),
            "FoundryGuideUsage");
        return new FoundryGuideClient(
            new HttpClient(handler),
            new StubCredential(),
            configuration,
            options);
    }

    private static ClaimsPrincipal Principal(string tenantId, string userId) =>
        new(new ClaimsIdentity(
            [
                new Claim("tid", tenantId),
                new Claim("oid", userId),
            ],
            "test"));

    private sealed class StubHandler(string responseBody) : HttpMessageHandler
    {
        internal string? RequestBody { get; private set; }

        internal string? UserIsolationKey { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            RequestBody = await request.Content!.ReadAsStringAsync(cancellationToken);
            UserIsolationKey = request.Headers.GetValues("x-ms-user-isolation-key").Single();
            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(responseBody),
            };
        }
    }

    private sealed class StubCredential : TokenCredential
    {
        public override AccessToken GetToken(
            TokenRequestContext requestContext,
            CancellationToken cancellationToken) =>
            new("token", DateTimeOffset.MaxValue);

        public override ValueTask<AccessToken> GetTokenAsync(
            TokenRequestContext requestContext,
            CancellationToken cancellationToken) =>
            ValueTask.FromResult(new AccessToken("token", DateTimeOffset.MaxValue));
    }
}
