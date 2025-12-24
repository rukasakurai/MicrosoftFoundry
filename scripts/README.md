# Agent Creation Scripts

This directory contains scripts for programmatically creating AI agents in Azure AI Foundry.

All commands in this document assume your current working directory is this `scripts/` folder.

## Available Implementations

### .NET (Default/Recommended) - `dotnet/CreateAgent/`
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

**Note:** This implementation uses the **classic Agents API** (`Azure.AI.Agents.Persistent`). Agents created with this SDK appear in the classic agent UI but not in the new Microsoft Foundry agent UI. Migration to the [new Agents API](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/migrate?view=foundry) is pending .NET SDK stabilization. See [migration guide](https://aka.ms/agent/migrate/tool) for the API differences.

### Python - `python/create-agent.py`
Python script using the Azure AI Projects SDK. Alternative option for Python-based workflows.

**Requirements:**
- Python 3.8+
- `pip install -r python/requirements.txt`

**Usage:**
```bash
# Use environment variables from azd
python python/create-agent.py

# Custom parameters
python python/create-agent.py --model-id gpt-4o --agent-name my-agent
```

### Bash/REST API - `create-agent.sh`
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

# OR Python
python python/create-agent.py

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
- Design Decision: Classic API vs New Agents API
  - Observed: SDK-created agents visible in classic agent UI only; new Foundry UI requires different API
  - Attempted: Migration to new Agents API (`Azure.AI.Projects` v1.0.0-beta.5) per [Microsoft Learn guide](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/migrate?view=foundry)
  - Issue: SDK beta.5 API surface doesn't match documentation (missing types: `PromptAgentDefinition`, `ConnectionProvider`; missing member: `AIProjectClient.Agents`)
  - Decision: **Reverted to classic API** (`Azure.AI.Agents.Persistent` v1.2.0-beta.8) which remains stable and functional
  - Future: Migration to new API pending .NET SDK stabilization - see [migration guide](https://aka.ms/agent/migrate/tool)
