# Agent Creation Scripts

This directory contains scripts for programmatically creating AI agents in Azure AI Foundry.

## Available Implementations

### .NET (Default/Recommended) - `dotnet/CreateAgent/`
.NET console application using the Azure AI Agents SDK. Provides strong typing, comprehensive error handling, and native Azure integration. **This is the recommended approach for this repository.**

**Requirements:**
- .NET 9.0 or higher
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
./create-agent.sh --model gpt-4-turbo --name my-agent
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
