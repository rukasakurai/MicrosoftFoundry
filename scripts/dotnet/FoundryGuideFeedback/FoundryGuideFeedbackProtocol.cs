using System.Text;
using System.Text.Json;
using Azure.Core;

internal static class FoundryGuideFeedbackProtocol
{
    internal static readonly TokenRequestContext TokenContext =
        new(["https://ai.azure.com/.default"]);

    internal static void ConfigureAuthorization(
        HttpClient httpClient,
        AccessToken token)
    {
        httpClient.DefaultRequestHeaders.Authorization =
            new("Bearer", token.Token);
    }

    internal static async Task<string> CreateConversationAsync(
        HttpClient httpClient,
        string endpoint,
        string prompt,
        CancellationToken cancellationToken = default)
    {
        var body = JsonSerializer.Serialize(new
        {
            items = new[]
            {
                new
                {
                    type = "message",
                    role = "user",
                    content = prompt,
                },
            },
        });

        using var response = await httpClient.PostAsync(
            $"{endpoint}/conversations?api-version=v1",
            new StringContent(body, Encoding.UTF8, "application/json"),
            cancellationToken);

        var content = await response.Content.ReadAsStringAsync(cancellationToken);
        EnsureSuccess(response, content, "create conversation");

        using var document = JsonDocument.Parse(content);
        if (document.RootElement.TryGetProperty("id", out var id))
        {
            return id.GetString()
                ?? throw new InvalidOperationException("Conversation id was empty.");
        }

        throw new InvalidOperationException(
            "Conversation response did not include an id.");
    }

    internal static async Task<JsonDocument> CreateAgentResponseAsync(
        HttpClient httpClient,
        string endpoint,
        string conversationId,
        string agentName,
        string agentVersion,
        CancellationToken cancellationToken = default)
    {
        var body = JsonSerializer.Serialize(new
        {
            conversation = conversationId,
            agent_reference = new
            {
                type = "agent_reference",
                name = agentName,
                version = agentVersion,
            },
        });

        using var response = await httpClient.PostAsync(
            $"{endpoint}/openai/v1/responses",
            new StringContent(body, Encoding.UTF8, "application/json"),
            cancellationToken);

        var content = await response.Content.ReadAsStringAsync(cancellationToken);
        EnsureSuccess(response, content, "create agent response");
        return JsonDocument.Parse(content);
    }

    internal static string ExtractResponseText(JsonDocument document)
    {
        if (document.RootElement.TryGetProperty("output_text", out var outputText)
            && outputText.ValueKind == JsonValueKind.String)
        {
            return outputText.GetString() ?? string.Empty;
        }

        var texts = new List<string>();
        CollectMessageText(document.RootElement, texts);
        return texts.Count > 0
            ? string.Join(Environment.NewLine, texts.Distinct())
            : document.RootElement.GetRawText();
    }

    private static void CollectMessageText(
        JsonElement element,
        List<string> texts)
    {
        if (element.ValueKind == JsonValueKind.Object)
        {
            if (element.TryGetProperty("type", out var type)
                && type.GetString() is "output_text" or "text"
                && element.TryGetProperty("text", out var text)
                && text.ValueKind == JsonValueKind.String)
            {
                var value = text.GetString();
                if (!string.IsNullOrWhiteSpace(value))
                {
                    texts.Add(value);
                }
            }

            foreach (var property in element.EnumerateObject())
            {
                CollectMessageText(property.Value, texts);
            }
        }
        else if (element.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in element.EnumerateArray())
            {
                CollectMessageText(item, texts);
            }
        }
    }

    private static void EnsureSuccess(
        HttpResponseMessage response,
        string content,
        string action)
    {
        if (response.IsSuccessStatusCode)
        {
            return;
        }

        throw new InvalidOperationException(
            $"Failed to {action}. HTTP {(int)response.StatusCode} "
            + $"{response.ReasonPhrase}: {content}");
    }
}
