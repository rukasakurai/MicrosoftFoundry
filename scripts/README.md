# Agent Scripts

This directory contains scripts for programmatically creating and managing AI agents in Microsoft Foundry.

All commands in this document assume your current working directory is this `scripts/` folder.

## Available Scripts

### Agent Creation

#### .NET (Default/Recommended) - `dotnet/CreateAgent/`
.NET console application using the Azure AI Agents SDK. Provides strong typing, comprehensive error handling, and native Azure integration. **This is the recommended approach for this repository.**

**Requirements:**
- .NET 10 or higher
- Azure CLI authenticated (`az login`) or appropriate Azure credentials

**Usage:**
```bash
cd dotnet/CreateAgent

# Use environment variables from azd
dotnet run

# Custom parameters
dotnet run -- --model-id gpt-4o --agent-name my-agent --help
```

See [dotnet/README.md](dotnet/README.md) for detailed instructions.

#### Bash/REST API - `create-agent.sh`
Bash script using Azure CLI and REST API. Perfect for CI/CD pipelines and shell-based automation.

**Requirements:**
- Bash shell
- Azure CLI (`az login`)
- `jq` (optional, for JSON formatting)

**Usage:**
```bash
# Use environment variables from azd
./create-agent.sh

# Custom parameters
./create-agent.sh --model gpt-4o --name my-agent
```

### Microsoft Entra Agent ID Registration - `register-agent-entra.sh`

Bash script to register agents with Microsoft Entra Agent ID, making them visible in the [Microsoft Entra admin center](https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/AllAgents.MenuView/~/overview).

**Requirements:**
- Bash shell
- Azure CLI (`az login`)
- Microsoft Entra Agent Registry Administrator role
- Microsoft Graph API permission: `AgentInstance.ReadWrite.All`
- `jq` (optional, for JSON formatting)

**Usage:**
```bash
# Register an agent with Microsoft Entra Agent ID
./register-agent-entra.sh --agent-name foundry-agent --display-name "My Foundry Agent"

# Full customization
./register-agent-entra.sh \
  --agent-name customer-service-agent \
  --display-name "Customer Service AI Agent" \
  --agent-url "https://myproject.services.ai.azure.com/api/agents/customer-service"
```

See [docs/entra-agent-registry.md](../docs/entra-agent-registry.md) for detailed setup instructions and prerequisites.

## Getting Environment Variables

All scripts work with environment variables from your azd deployment:

```bash
# Load environment variables
eval $(azd env get-values)

# Verify variables are set
echo $COGNITIVE_SERVICES_ENDPOINT
echo $PROJECT_NAME

# Run .NET (recommended)
cd dotnet/CreateAgent && dotnet run

# OR Bash
./create-agent.sh
```

## Documentation

For comprehensive documentation, examples, and troubleshooting, see [docs/agent-creation.md](../docs/agent-creation.md).

## Documentation Test History
### 2025-12-24
- Result: PASS with fixes and design decisions
- Platform/Context: VS Code local workspace
- OS: Windows 10 Enterprise 2009 (build 26200.7392)
- Shell: PowerShell 7.5.4 (Core)
- Tester: Automated Documentation Tester (with human intervention)
- Notes: 
  - Fixed: Added PROJECT_ENDPOINT output to infra/main.bicep
  - Fixed: Updated Program.cs to prioritize PROJECT_ENDPOINT over COGNITIVE_SERVICES_ENDPOINT
  - Fixed: Updated .NET version requirement from 9.0 to 10
  - Fixed: Updated bash example to use gpt-4o instead of gpt-4-turbo
  - Fixed: Added working directory clarification
  - Verified: Agents successfully created and retrievable via REST API at project endpoint
- Migrated to new Agents API (`Azure.AI.Projects.OpenAI` v1.0.0-beta.3) per [Microsoft Learn guide](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/migrate?view=foundry)
  - Updated SDK package and API calls to use agent versioning
  - REST API endpoints updated to use conversations and responses
