# Agent Creation Scripts

This directory contains scripts for programmatically creating AI agents in Microsoft Foundry.

## Available Scripts

### `create-agent.py`
Python script using the Azure AI Projects SDK to create agents. Provides strong typing, comprehensive error handling, and is ideal for integration into Python applications.

**Requirements:**
- Python 3.8+
- `pip install azure-ai-projects azure-identity`

**Usage:**
```bash
# Use environment variables from azd
python create-agent.py

# Custom parameters
python create-agent.py --model-id gpt-4o --agent-name my-agent
```

### `create-agent.sh`
Bash script using Azure CLI and REST API to create agents. Perfect for CI/CD pipelines and shell-based automation.

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

Both scripts work with environment variables from your azd deployment:

```bash
# Load environment variables
eval $(azd env get-values)

# Verify variables are set
echo $COGNITIVE_SERVICES_ENDPOINT
echo $PROJECT_NAME

# Run scripts
python create-agent.py
# OR
./create-agent.sh
```

## Documentation

For comprehensive documentation, examples, and troubleshooting, see [docs/agent-creation.md](../docs/agent-creation.md).
