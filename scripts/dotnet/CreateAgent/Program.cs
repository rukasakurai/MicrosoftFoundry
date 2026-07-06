using Azure.AI.Projects;
using Azure.AI.Projects.Agents;
using Azure.Identity;

/// <summary>
/// Create an AI agent in Microsoft Foundry using the .NET SDK.
/// 
/// This program demonstrates how to programmatically create an agent in a Microsoft Foundry
/// project that has been provisioned with Bicep templates.
/// 
/// Prerequisites:
/// - Azure CLI installed and authenticated (az login) or appropriate Azure credentials
/// - .NET 10 or higher
/// - Azure.AI.Projects, Azure.AI.Projects.Agents, and Azure.Identity NuGet packages
/// 
/// Usage:
///   # Using environment variables from azd
///   dotnet run
/// 
///   # Or specify parameters explicitly
///   dotnet run -- --project-endpoint <endpoint> --model-id <model>
/// 
/// Environment Variables (from 'azd env get-values'):
///   PROJECT_ENDPOINT: Microsoft Foundry project endpoint URL (primary)
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
            string modelId = "gpt-5.4";
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

            // Authenticate with the Azure CLI sign-in (az login), matching
            // scripts/create-agent.sh. AzureCliCredential is used instead of
            // DefaultAzureCredential so local runs don't stall ~3 minutes probing
            // the (unavailable) Managed Identity endpoint before falling back.
            var credential = new AzureCliCredential();

            // Create project client for new agents API
            var projectClient = new AIProjectClient(
                endpoint: new Uri(projectEndpoint),
                tokenProvider: credential);

            // Define the agent (declarative / prompt-based)
            var agentDefinition = new DeclarativeAgentDefinition(model: modelId)
            {
                Instructions = agentInstructions
            };

            // Create a new agent version
            var agentVersion = (await projectClient.AgentAdministrationClient.CreateAgentVersionAsync(
                agentName: agentName,
                options: new ProjectsAgentVersionCreationOptions(agentDefinition)
                {
                    Description = agentDescription
                })).Value;

            Console.WriteLine("✓ Agent created successfully!");
            Console.WriteLine($"  Agent ID: {agentVersion.Name}:{agentVersion.Version}");
            Console.WriteLine($"  Agent Name: {agentVersion.Name}");
            Console.WriteLine($"  Version: {agentVersion.Version}");
            Console.WriteLine($"  Model: {agentDefinition.Model}");
            Console.WriteLine();
            Console.WriteLine("".PadRight(60, '='));
            Console.WriteLine("Agent creation completed successfully!");
            Console.WriteLine("".PadRight(60, '='));
            Console.WriteLine();
            Console.WriteLine("Next steps:");
            Console.WriteLine("  1. View your agent in Microsoft Foundry portal");
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
        Console.WriteLine("Create an AI agent in Microsoft Foundry using the .NET SDK.");
        Console.WriteLine();
        Console.WriteLine("Options:");
        Console.WriteLine("  --project-endpoint, -e <url>    Microsoft Foundry project endpoint (default: from PROJECT_ENDPOINT env var)");
        Console.WriteLine("  --model-id, -m <id>             Model deployment ID (default: gpt-5.4)");
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
        Console.WriteLine("    --model-id gpt-5.4 \\");
        Console.WriteLine("    --agent-name custom-agent \\");
        Console.WriteLine("    --agent-instructions \"You are a specialized customer service agent\" \\");
        Console.WriteLine("    --agent-description \"Customer service automation agent\"");
    }
}
