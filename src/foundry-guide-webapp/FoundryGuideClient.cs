using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Azure.Core;

internal sealed class FoundryGuideClient(
    HttpClient httpClient,
    TokenCredential credential,
    IConfiguration configuration)
{
    private static readonly TokenRequestContext TokenContext = new(["https://ai.azure.com/.default"]);
    private readonly string _projectEndpoint = Require(configuration["PROJECT_ENDPOINT"], "PROJECT_ENDPOINT").TrimEnd('/');
    private readonly string _agentName = configuration["FOUNDRY_GUIDE_AGENT_NAME"] ?? "foundry-guide";

    internal async Task<FoundryResponse> SendAsync(
        string input,
        string? previousResponseId,
        string userId,
        string chatId,
        CancellationToken cancellationToken)
    {
        var token = await credential.GetTokenAsync(TokenContext, cancellationToken);
        using var request = new HttpRequestMessage(
            HttpMethod.Post,
            $"{_projectEndpoint}/agents/{Uri.EscapeDataString(_agentName)}/endpoint/protocols/openai/responses");

        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token.Token);
        request.Headers.Add("user_isolation_key", HashUserId(userId));
        request.Headers.Add("chat_isolation_key", chatId);

        var payload = new Dictionary<string, object?>
        {
            ["input"] = input,
        };
        if (!string.IsNullOrWhiteSpace(previousResponseId))
        {
            payload["previous_response_id"] = previousResponseId;
        }

        request.Content = new StringContent(
            JsonSerializer.Serialize(payload),
            Encoding.UTF8,
            "application/json");

        using var response = await httpClient.SendAsync(request, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            throw new FoundryServiceException((int)response.StatusCode);
        }

        await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
        using var document = await JsonDocument.ParseAsync(stream, cancellationToken: cancellationToken);

        var responseId = document.RootElement.TryGetProperty("id", out var id)
            ? id.GetString()
            : null;
        if (string.IsNullOrWhiteSpace(responseId))
        {
            throw new InvalidOperationException("Foundry response did not include an id.");
        }

        return new FoundryResponse(responseId, ExtractResponseText(document.RootElement));
    }

    private static string ExtractResponseText(JsonElement root)
    {
        if (root.TryGetProperty("output_text", out var outputText)
            && outputText.ValueKind == JsonValueKind.String
            && !string.IsNullOrWhiteSpace(outputText.GetString()))
        {
            return outputText.GetString()!;
        }

        var text = new List<string>();
        CollectText(root, text);
        if (text.Count == 0)
        {
            throw new InvalidOperationException("Foundry response did not include output text.");
        }

        return string.Join(Environment.NewLine, text.Distinct());
    }

    private static void CollectText(JsonElement element, List<string> text)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            if (element.TryGetProperty("type", out var type)
                && type.GetString() is "output_text" or "text"
                && element.TryGetProperty("text", out var value)
                && value.ValueKind == JsonValueKind.String
                && !string.IsNullOrWhiteSpace(value.GetString()))
            {
                text.Add(value.GetString()!);
            }

            foreach (var property in element.EnumerateObject())
            {
                CollectText(property.Value, text);
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in element.EnumerateArray())
            {
                CollectText(item, text);
            }
        }
    }

    private static string HashUserId(string userId) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(userId))).ToLowerInvariant();

    private static string Require(string? value, string name) =>
        string.IsNullOrWhiteSpace(value)
            ? throw new InvalidOperationException($"{name} is required.")
            : value;
}

internal sealed record FoundryResponse(string Id, string Text);

internal sealed class FoundryServiceException(int statusCode)
    : Exception($"Foundry request failed with HTTP {statusCode}.")
{
    internal int StatusCode { get; } = statusCode;
}
