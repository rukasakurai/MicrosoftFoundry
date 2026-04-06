using Azure.AI.OpenAI;
using Azure.Identity;
using OpenAI.Chat;

/// <summary>
/// Verify that cached_tokens is returned in streaming Chat Completions usage chunks
/// when stream_options: {"include_usage": true} is set.
///
/// This program sends two identical streaming requests to verify:
/// 1. First request: cached_tokens is 0 (no cache yet)
/// 2. Second request: cached_tokens > 0 (cache hit)
///
/// Prerequisites:
/// - Azure CLI installed and authenticated (az login) or appropriate Azure credentials
/// - .NET 10 or higher
/// - A model deployment (e.g., gpt-5.2) on Microsoft Foundry
///
/// Usage:
///   # Using environment variables from azd
///   dotnet run -- --deployment gpt-5.2
///
///   # Or specify parameters explicitly
///   dotnet run -- --endpoint <endpoint> --deployment <deployment-name>
///
/// Environment Variables (from 'azd env get-values'):
///   COGNITIVE_SERVICES_ENDPOINT: Azure AI Services endpoint URL
/// </summary>

class Program
{
    static async Task<int> Main(string[] args)
    {
        try
        {
            // Parse command line arguments
            string? endpoint = null;
            string? deploymentName = null;

            for (int i = 0; i < args.Length; i++)
            {
                switch (args[i])
                {
                    case "--endpoint" or "-e":
                        if (i + 1 < args.Length) endpoint = args[++i];
                        break;
                    case "--deployment" or "-d":
                        if (i + 1 < args.Length) deploymentName = args[++i];
                        break;
                    case "--help" or "-h":
                        PrintUsage();
                        return 0;
                }
            }

            // Get endpoint from environment if not provided
            if (string.IsNullOrEmpty(endpoint))
            {
                endpoint = Environment.GetEnvironmentVariable("COGNITIVE_SERVICES_ENDPOINT");
                if (string.IsNullOrEmpty(endpoint))
                {
                    Console.Error.WriteLine("Error: COGNITIVE_SERVICES_ENDPOINT environment variable not found.");
                    Console.Error.WriteLine("Run 'eval $(azd env get-values)' or provide --endpoint parameter.");
                    return 1;
                }
            }

            if (string.IsNullOrEmpty(deploymentName))
            {
                Console.Error.WriteLine("Error: --deployment parameter is required (e.g., --deployment gpt-5.2).");
                return 1;
            }

            Console.WriteLine("================================================================");
            Console.WriteLine("Verifying cached_tokens in streaming usage chunks");
            Console.WriteLine("================================================================");
            Console.WriteLine();
            Console.WriteLine($"  Endpoint:   {endpoint}");
            Console.WriteLine($"  Deployment: {deploymentName}");
            Console.WriteLine();

            // Authenticate using DefaultAzureCredential
            var credential = new DefaultAzureCredential();
            var client = new AzureOpenAIClient(new Uri(endpoint), credential);
            var chatClient = client.GetChatClient(deploymentName);

            // Generate a long prompt (>= 1024 tokens) to meet prompt caching minimum
            var longContent = GenerateLongPrompt();

            var messages = new List<ChatMessage>
            {
                new SystemChatMessage("You are a helpful assistant. Respond briefly."),
                new UserChatMessage(longContent)
            };

            // The SDK automatically sets stream_options: {"include_usage": true}
            // when using CompleteChatStreamingAsync, so the final streaming chunk
            // will include usage information.
            var options = new ChatCompletionOptions
            {
                MaxOutputTokenCount = 50
            };

            // First request (should have cached_tokens = 0)
            Console.WriteLine("--- Request 1 ---");
            Console.WriteLine("Sending streaming Chat Completions request...");
            Console.WriteLine();
            await SendStreamingRequest(chatClient, messages, options, requestNumber: 1);

            // Brief pause to allow cache to be established
            Console.WriteLine("Waiting 3 seconds for cache to be established...");
            await Task.Delay(3000);
            Console.WriteLine();

            // Second request (should have cached_tokens > 0)
            Console.WriteLine("--- Request 2 ---");
            Console.WriteLine("Sending streaming Chat Completions request...");
            Console.WriteLine();
            await SendStreamingRequest(chatClient, messages, options, requestNumber: 2);

            Console.WriteLine("================================================================");
            Console.WriteLine("Verification complete.");
            Console.WriteLine("================================================================");
            Console.WriteLine();
            Console.WriteLine($"  Model deployment: {deploymentName}");
            Console.WriteLine($"  Endpoint:         {endpoint}");
            Console.WriteLine();
            Console.WriteLine("See docs/streaming-cached-tokens.md for more information.");

            return 0;
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"\nError: {ex.Message}");
            if (ex.InnerException != null)
            {
                Console.Error.WriteLine($"  Inner Exception: {ex.InnerException.Message}");
            }
            return 1;
        }
    }

    static async Task SendStreamingRequest(
        ChatClient chatClient,
        List<ChatMessage> messages,
        ChatCompletionOptions options,
        int requestNumber)
    {
        int? promptTokens = null;
        int? completionTokens = null;
        int? cachedTokens = null;
        bool hasPromptDetails = false;

        await foreach (var update in chatClient.CompleteChatStreamingAsync(messages, options))
        {
            // Check for usage information in the streaming update
            if (update.Usage is not null)
            {
                promptTokens = update.Usage.InputTokenCount;
                completionTokens = update.Usage.OutputTokenCount;

                if (update.Usage.InputTokenDetails is not null)
                {
                    hasPromptDetails = true;
                    cachedTokens = update.Usage.InputTokenDetails.CachedTokenCount;
                }

                Console.WriteLine("Usage chunk found:");
                Console.WriteLine($"  prompt_tokens:     {promptTokens}");
                Console.WriteLine($"  completion_tokens: {completionTokens}");
                Console.WriteLine($"  prompt_tokens_details present: {hasPromptDetails}");
                Console.WriteLine($"  cached_tokens:     {cachedTokens?.ToString() ?? "(not present)"}");
                Console.WriteLine();
            }
        }

        // Validate acceptance criteria
        if (promptTokens is null)
        {
            Console.WriteLine("  ✗ FAIL: prompt_tokens is not populated");
        }
        else
        {
            Console.WriteLine($"  ✓ PASS: prompt_tokens is populated ({promptTokens})");
        }

        if (completionTokens is null)
        {
            Console.WriteLine("  ✗ FAIL: completion_tokens is not populated");
        }
        else
        {
            Console.WriteLine($"  ✓ PASS: completion_tokens is populated ({completionTokens})");
        }

        if (!hasPromptDetails)
        {
            Console.WriteLine("  ✗ FAIL: prompt_tokens_details is not present");
        }
        else
        {
            Console.WriteLine("  ✓ PASS: prompt_tokens_details is present");
        }

        if (requestNumber == 1)
        {
            if (cachedTokens is not null && cachedTokens == 0)
            {
                Console.WriteLine("  ✓ PASS: cached_tokens is 0 (no cache on first request)");
            }
            else if (cachedTokens is null)
            {
                Console.WriteLine("  ? INFO: cached_tokens not present on first request");
            }
            else
            {
                Console.WriteLine($"  ? INFO: cached_tokens is {cachedTokens} on first request (cache may already exist)");
            }
        }
        else
        {
            if (cachedTokens is not null && cachedTokens > 0)
            {
                Console.WriteLine($"  ✓ PASS: cached_tokens is {cachedTokens} (cache hit on second request)");
            }
            else if (cachedTokens is not null && cachedTokens == 0)
            {
                Console.WriteLine("  ✗ FAIL: cached_tokens is 0 (expected cache hit on second request)");
            }
            else
            {
                Console.WriteLine($"  ? INFO: cached_tokens is {cachedTokens?.ToString() ?? "not present"}");
            }
        }

        Console.WriteLine();
    }

    static string GenerateLongPrompt()
    {
        // Generate a prompt with >= 1024 tokens to meet prompt caching minimum
        const string paragraph =
            "The quick brown fox jumps over the lazy dog. " +
            "This is a test of the prompt caching mechanism in Azure OpenAI and Microsoft Foundry. " +
            "We need to ensure that the prompt is long enough to meet the minimum token threshold " +
            "for prompt caching to be triggered. Prompt caching is a feature that allows the API " +
            "to cache the processing of long prompts so that subsequent requests with the same " +
            "prefix can be served faster and at lower cost. The cache is based on exact token " +
            "prefix matching, meaning the first N tokens must be identical for a cache hit to " +
            "occur. This paragraph is being repeated multiple times to generate a prompt that " +
            "exceeds 1024 tokens, which is the minimum threshold for prompt caching to activate. " +
            "Each repetition adds approximately 120 tokens to the total prompt length, so we " +
            "need at least 9 repetitions to exceed the threshold. The model will process the " +
            "cached prefix more efficiently on the second request, and the usage object should " +
            "reflect this with a non-zero cached_tokens value in the prompt_tokens_details field.";

        var parts = new List<string>();
        for (int i = 1; i <= 12; i++)
        {
            parts.Add($"Repetition {i}: {paragraph}");
        }

        return string.Join(" ", parts);
    }

    static void PrintUsage()
    {
        Console.WriteLine("Usage: VerifyStreamingCachedTokens [OPTIONS]");
        Console.WriteLine();
        Console.WriteLine("Verify cached_tokens in streaming Chat Completions usage chunks.");
        Console.WriteLine();
        Console.WriteLine("Options:");
        Console.WriteLine("  --endpoint, -e <url>       Azure AI Services endpoint (default: from COGNITIVE_SERVICES_ENDPOINT env var)");
        Console.WriteLine("  --deployment, -d <name>    Model deployment name (required, e.g., gpt-5.2)");
        Console.WriteLine("  --help, -h                 Show this help message");
        Console.WriteLine();
        Console.WriteLine("Examples:");
        Console.WriteLine("  # Use environment variables from azd");
        Console.WriteLine("  dotnet run -- --deployment gpt-5.2");
        Console.WriteLine();
        Console.WriteLine("  # Specify endpoint explicitly");
        Console.WriteLine("  dotnet run -- --endpoint https://cog-abc123.cognitiveservices.azure.com --deployment gpt-5.2");
    }
}
