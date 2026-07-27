using System.Net;
using System.Security.Claims;
using System.Text.Json;
using Azure.Core;
using Microsoft.Extensions.Configuration;
using Xunit;

public sealed class FoundryGuideClientTests
{
    [Fact]
    public void ConfiguresFortySecondRequestTimeout()
    {
        using var httpClient = new HttpClient();

        FoundryGuideClient.ConfigureHttpClient(httpClient);

        Assert.Equal(TimeSpan.FromSeconds(40), httpClient.Timeout);
    }

    [Fact]
    public async Task SendsStableAgentRequestWithIsolationAndChaining()
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
        var credential = new StubCredential();
        var client = CreateClient(handler, credential);
        var chatId = Guid.NewGuid().ToString("N");

        var response = await client.SendAsync(
            "Hello",
            "resp_previous",
            "subject",
            chatId,
            TestContext.Current.CancellationToken);

        Assert.Equal("resp_test", response.Id);
        Assert.Equal("OK", response.Text);
        Assert.Equal(new FoundryTokenUsage(145, 5, 150), response.Usage);
        Assert.Equal(
            "https://contoso.services.ai.azure.com/api/projects/guide/agents/foundry-guide/endpoint/protocols/openai/responses?api-version=v1",
            handler.RequestUri?.ToString());
        Assert.Equal("Bearer", handler.AuthorizationScheme);
        Assert.Equal("token", handler.AuthorizationParameter);
        Assert.Equal("subject", handler.UserIsolationKey);
        Assert.Equal(chatId, handler.ChatIsolationKey);
        Assert.Equal(
            ["https://ai.azure.com/.default"],
            Assert.IsType<string[]>(credential.Scopes));

        using var payload = JsonDocument.Parse(Assert.IsType<string>(handler.RequestBody));
        Assert.Equal("Hello", payload.RootElement.GetProperty("input").GetString());
        Assert.Equal(
            "resp_previous",
            payload.RootElement.GetProperty("previous_response_id").GetString());
        Assert.Equal(128, payload.RootElement.GetProperty("max_output_tokens").GetInt32());
        Assert.False(payload.RootElement.GetProperty("stream").GetBoolean());
    }

    [Fact]
    public async Task ExtractsDistinctNestedResponseText()
    {
        var client = CreateClient(
            new StubHandler(
                """
                {
                  "id": "resp_test",
                  "output": [{
                    "content": [
                      { "type": "output_text", "text": "First" },
                      { "type": "output_text", "text": "First" },
                      { "type": "text", "text": "Second" }
                    ]
                  }],
                  "usage": {
                    "input_tokens": 10,
                    "output_tokens": 2,
                    "total_tokens": 12
                  }
                }
                """));

        var response = await client.SendAsync(
            "Hello",
            null,
            "subject",
            Guid.NewGuid().ToString("N"),
            TestContext.Current.CancellationToken);

        Assert.Equal($"First{Environment.NewLine}Second", response.Text);
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
    public async Task RejectsResponseWithoutOutputTextAsInvalidData()
    {
        var client = CreateClient(
            new StubHandler(
                """
                {
                  "id": "resp_test",
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
    public async Task PreservesFoundryFailureStatus()
    {
        var client = CreateClient(
            new StubHandler(
                """{"error":{"code":"rate_limit"}}""",
                HttpStatusCode.TooManyRequests));

        var exception = await Assert.ThrowsAsync<FoundryServiceException>(() =>
            client.SendAsync(
                "Hello",
                null,
                "subject",
                Guid.NewGuid().ToString("N"),
                TestContext.Current.CancellationToken));

        Assert.Equal(429, exception.StatusCode);
    }

    [Fact]
    public async Task HonorsHttpClientTimeout()
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
                    "total_tokens": 150
                  }
                }
                """,
                delay: TimeSpan.FromSeconds(1)),
            timeout: TimeSpan.FromMilliseconds(20));

        await Assert.ThrowsAnyAsync<OperationCanceledException>(() =>
            client.SendAsync(
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

    private static FoundryGuideClient CreateClient(
        StubHandler handler,
        StubCredential? credential = null,
        TimeSpan? timeout = null)
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
        var httpClient = new HttpClient(handler);
        if (timeout.HasValue)
        {
            httpClient.Timeout = timeout.Value;
        }

        return new FoundryGuideClient(
            httpClient,
            credential ?? new StubCredential(),
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

    private sealed class StubHandler(
        string responseBody,
        HttpStatusCode statusCode = HttpStatusCode.OK,
        TimeSpan? delay = null) : HttpMessageHandler
    {
        internal string? RequestBody { get; private set; }

        internal Uri? RequestUri { get; private set; }

        internal string? AuthorizationScheme { get; private set; }

        internal string? AuthorizationParameter { get; private set; }

        internal string? UserIsolationKey { get; private set; }

        internal string? ChatIsolationKey { get; private set; }

        protected override async Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            if (delay.HasValue)
            {
                await Task.Delay(delay.Value, cancellationToken);
            }

            RequestUri = request.RequestUri;
            AuthorizationScheme = request.Headers.Authorization?.Scheme;
            AuthorizationParameter = request.Headers.Authorization?.Parameter;
            RequestBody = await request.Content!.ReadAsStringAsync(cancellationToken);
            UserIsolationKey = request.Headers.GetValues("x-ms-user-isolation-key").Single();
            ChatIsolationKey = request.Headers.GetValues("x-ms-chat-isolation-key").Single();
            return new HttpResponseMessage(statusCode)
            {
                Content = new StringContent(responseBody),
            };
        }
    }

    private sealed class StubCredential : TokenCredential
    {
        internal string[]? Scopes { get; private set; }

        public override AccessToken GetToken(
            TokenRequestContext requestContext,
            CancellationToken cancellationToken)
        {
            Scopes = requestContext.Scopes.ToArray();
            return new AccessToken("token", DateTimeOffset.MaxValue);
        }

        public override ValueTask<AccessToken> GetTokenAsync(
            TokenRequestContext requestContext,
            CancellationToken cancellationToken)
        {
            Scopes = requestContext.Scopes.ToArray();
            return ValueTask.FromResult(new AccessToken("token", DateTimeOffset.MaxValue));
        }
    }
}
