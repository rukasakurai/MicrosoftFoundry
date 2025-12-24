using Azure.AI.Agents.Persistent;
using Azure.Identity;

/// <summary>
/// Create an AI agent in Azure AI Foundry using the .NET SDK.
/// 
/// This program demonstrates how to programmatically create an agent in a Microsoft Foundry
/// project that has been provisioned with Bicep templates.
/// 
/// Prerequisites:
/// - Azure CLI installed and authenticated (az login) or appropriate Azure credentials
/// - .NET 9.0 or higher
/// - Azure.AI.Agents.Persistent and Azure.Identity NuGet packages
/// 
/// Usage:
///   # Using environment variables from azd
///   dotnet run
/// 
///   # Or specify parameters explicitly
///   dotnet run -- --project-endpoint <endpoint> --model-id <model>
/// 
/// Environment Variables (from 'azd env get-values'):
///   PROJECT_ENDPOINT: Azure AI Foundry project endpoint URL (primary)
///   COGNITIVE_SERVICES_ENDPOINT: Azure AI Services endpoint URL (fallback)
///   PROJECT_NAME: Name of the Foundry project (not used in SDK, but available)
/// </summary>

class Program
{
    static async Task<int> Main(string[] args)
    {
        try
        {
            // Parse command line arguments
            string? projectEndpoint = null;
            string modelId = "gpt-4o";
            string agentName = "foundry-agent";
            string agentInstructions = "You are a helpful AI assistant.";
            string agentDescription = "Agent created programmatically via .NET SDK";

            for (int i = 0; i < args.Length; i++)
            {
                switch (args[i])
                {
                    case "--project-endpoint" or "-e":
                        if (i + 1 < args.Length) projectEndpoint = args[++i];
                        break;
                    case "--model-id" or "-m":
                        if (i + 1 < args.Length) modelId = args[++i];
                        break;
                    case "--agent-name" or "-n":
                        if (i + 1 < args.Length) agentName = args[++i];
                        break;
                    case "--agent-instructions" or "-i":
                        if (i + 1 < args.Length) agentInstructions = args[++i];
                        break;
                    case "--agent-description" or "-d":
                        if (i + 1 < args.Length) agentDescription = args[++i];
                        break;
                    case "--help" or "-h":
                        PrintUsage();
                        return 0;
                }
            }

            // Get project endpoint from environment if not provided
            if (string.IsNullOrEmpty(projectEndpoint))
            {
                // Try PROJECT_ENDPOINT first (from azd), then COGNITIVE_SERVICES_ENDPOINT as fallback
                projectEndpoint = Environment.GetEnvironmentVariable("PROJECT_ENDPOINT") 
                    ?? Environment.GetEnvironmentVariable("COGNITIVE_SERVICES_ENDPOINT");
                
                if (string.IsNullOrEmpty(projectEndpoint))
                {
                    Console.Error.WriteLine("Error: Neither PROJECT_ENDPOINT nor COGNITIVE_SERVICES_ENDPOINT environment variable found.");
                    Console.Error.WriteLine("Run 'azd env get-values' or provide --project-endpoint parameter.");
                    return 1;
                }
            }

            Console.WriteLine($"Creating agent '{agentName}' in project...");
            Console.WriteLine($"  Endpoint: {projectEndpoint}");
            Console.WriteLine($"  Model: {modelId}");
            Console.WriteLine();

            // Authenticate using DefaultAzureCredential
            // This supports multiple authentication methods:
            // - Environment variables
            // - Managed Identity
            // - Azure CLI (az login)
            // - Azure PowerShell
            // - Interactive browser
            var credential = new DefaultAzureCredential();

            // Create project client with persistent agents
            var agentsClient = new PersistentAgentsClient(projectEndpoint, credential);

            // Create agent
            var agent = await agentsClient.Administration.CreateAgentAsync(
                model: modelId,
                name: agentName,
                instructions: agentInstructions,
                description: agentDescription);

            Console.WriteLine("✓ Agent created successfully!");
            Console.WriteLine($"  Agent ID: {agent.Value.Id}");
            Console.WriteLine($"  Agent Name: {agent.Value.Name}");
            Console.WriteLine($"  Model: {agent.Value.Model}");
            Console.WriteLine();
            Console.WriteLine("".PadRight(60, '='));
            Console.WriteLine("Agent creation completed successfully!");
            Console.WriteLine("".PadRight(60, '='));
            Console.WriteLine();
            Console.WriteLine("Next steps:");
            Console.WriteLine("  1. View your agent in Azure AI Foundry portal");
            Console.WriteLine("  2. Test the agent with a conversation thread");
            Console.WriteLine("  3. Publish the agent to an application for external access");
            Console.WriteLine();
            Console.WriteLine("For more information, see docs/agent-creation.md");

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

    static void PrintUsage()
    {
        Console.WriteLine("Usage: CreateAgent [OPTIONS]");
        Console.WriteLine();
        Console.WriteLine("Create an AI agent in Azure AI Foundry using the .NET SDK.");
        Console.WriteLine();
        Console.WriteLine("Options:");
        Console.WriteLine("  --project-endpoint, -e <url>    Azure AI Foundry project endpoint (default: from PROJECT_ENDPOINT env var)");
        Console.WriteLine("  --model-id, -m <id>             Model deployment ID (default: gpt-4o)");
        Console.WriteLine("  --agent-name, -n <name>         Agent name (default: foundry-agent)");
        Console.WriteLine("  --agent-instructions, -i <text> Agent instructions (default: 'You are a helpful AI assistant.')");
        Console.WriteLine("  --agent-description, -d <text>  Agent description (default: 'Agent created programmatically via .NET SDK')");
        Console.WriteLine("  --help, -h                      Show this help message");
        Console.WriteLine();
        Console.WriteLine("Examples:");
        Console.WriteLine("  # Use environment variables from azd");
        Console.WriteLine("  dotnet run");
        Console.WriteLine();
        Console.WriteLine("  # Specify custom parameters");
        Console.WriteLine("  dotnet run -- --model-id gpt-4-turbo --agent-name my-assistant");
        Console.WriteLine();
        Console.WriteLine("  # Full customization");
        Console.WriteLine("  dotnet run -- \\");
        Console.WriteLine("    --project-endpoint https://cog-abc123.services.ai.azure.com \\");
        Console.WriteLine("    --model-id gpt-4o \\");
        Console.WriteLine("    --agent-name custom-agent \\");
        Console.WriteLine("    --agent-instructions \"You are a specialized customer service agent\" \\");
        Console.WriteLine("    --agent-description \"Customer service automation agent\"");
    }
}
