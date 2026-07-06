# Programmatically Creating Agents in Microsoft Foundry

This guide explains how to programmatically create AI agents in your Microsoft Foundry project after provisioning infrastructure with Bicep templates.

## Overview

Microsoft Foundry agents are intelligent assistants powered by large language models (LLMs) that can be configured with custom instructions, tools, and capabilities. While the Bicep templates provision the infrastructure (AI Services, Projects, Applications, and Deployments), the actual agent logic must be created separately.

> **Note**: This guide uses the **new Microsoft Foundry Agents API** which creates versioned agents using the `/agents/{name}/versions` endpoint. This is the recommended approach going forward.

While various approaches exist, this repository focuses on programmatic agent creation with **REST API with Bash/Azure CLI**

## Prerequisites

- Microsoft Foundry infrastructure deployed (see [azd-deployment.md](./azd-deployment.md))
- Azure CLI installed and authenticated: `az login`
- Model deployments available in your Microsoft Foundry (Azure AI Services) account. `azd up` deploys one by default (`gpt-4o`, exposed as the `MODEL_DEPLOYMENT_NAME` output); override with the `modelDeploymentName`/`modelName`/`modelVersion` parameters.
- Bash shell:
  - **Linux/macOS**: Use the default terminal
  - **Windows**: Use [Git Bash](https://git-scm.com/downloads) (included with Git for Windows)
- `jq` (optional, for better JSON formatting)

> **API Version (as of December 2025)**: The new agents API requires preview API version `2025-05-15-preview`. The GA version `2025-05-01` only supports the classic assistants API. This may change as the API evolves.

## Quick Start

### Bash Script with REST API

The bash script is ideal for CI/CD pipelines and automation workflows.

**Windows Users**: Open **Git Bash** (not PowerShell or CMD) to run these commands.

```bash
# Get environment variables from azd and run script
# Note: Use && to chain commands so environment variables persist
eval $(azd env get-values) && ./scripts/create-agent.sh

# Or provide parameters explicitly
./scripts/create-agent.sh \
  --endpoint "${PROJECT_ENDPOINT}" \
  --project "${PROJECT_NAME}"
```

**Example with custom parameters:**

```bash
./scripts/create-agent.sh \
  --model gpt-4-turbo \
  --name my-agent \
  --instructions "You are a specialized AI assistant" \
  --description "Production agent for customer inquiries"
```

## Verifying Agent Creation

After creating an agent, you can verify it was created successfully by listing all agents or retrieving a specific agent:

### List All Agents

```bash
# Set environment variables
eval $(azd env get-values)

# Get access token
ACCESS_TOKEN=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)

# List all agents in the project
curl -X GET \
  "${PROJECT_ENDPOINT}/agents?api-version=2025-05-15-preview" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json"
```

### Get Specific Agent Version

```bash
# Replace with agent name and version from create-agent.sh
AGENT_NAME="foundry-agent"
AGENT_VERSION="1"

curl -X GET \
  "${PROJECT_ENDPOINT}/agents/${AGENT_NAME}/versions/${AGENT_VERSION}?api-version=2025-05-15-preview" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json"
```

The response will include all agent properties including name, model, instructions, and configuration.

## Agent Configuration Options

When creating an agent, you can configure various properties:

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `model` | string | Yes | Model deployment ID (e.g., "gpt-4o", "gpt-4-turbo") |
| `name` | string | No | Display name for the agent |
| `description` | string | No | Description of the agent's purpose |
| `instructions` | string | No | System instructions defining agent behavior |
| `temperature` | float | No | Sampling temperature (0-2, default: 1) |
| `top_p` | float | No | Nucleus sampling (0-1, default: 1) |
| `tools` | array | No | Array of tool definitions (Code Interpreter, File Search, etc.) |
| `tool_resources` | object | No | Resources for tools (file IDs, vector store IDs) |
| `metadata` | object | No | Custom key-value pairs (max 16) |
| `response_format` | string | No | Response format ("auto", "json_object", "text") |

### Available Tools

Microsoft Foundry agents support several built-in tools:

- **Code Interpreter**: Execute code
- **File Search**: Search through uploaded documents
- **Bing Grounding**: Web search capabilities
- **Function Calling**: Custom API integrations
- **Azure AI Search**: Enterprise search integration

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Deploy Agent

on:
  push:
    branches: [main]

jobs:
  deploy-agent:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Azure Login
        uses: azure/login@v1
        with:
          creds: ${{ secrets.AZURE_CREDENTIALS }}
      
      - name: Get Environment Variables
        run: |
          cd ${{ github.workspace }}
          azd env select production
          eval $(azd env get-values)
          echo "COGNITIVE_SERVICES_ENDPOINT=${COGNITIVE_SERVICES_ENDPOINT}" >> $GITHUB_ENV
          echo "PROJECT_NAME=${PROJECT_NAME}" >> $GITHUB_ENV
      
      - name: Create Agent
        run: |
          ./scripts/create-agent.sh \
            --model gpt-4o \
            --name production-agent \
            --instructions "$(cat agent-config/instructions.txt)"
```

### Azure DevOps Pipeline Example

```yaml
trigger:
  branches:
    include:
      - main

pool:
  vmImage: 'ubuntu-latest'

steps:
- task: AzureCLI@2
  displayName: 'Create Agent'
  inputs:
    azureSubscription: 'Azure-Service-Connection'
    scriptType: 'bash'
    scriptLocation: 'scriptPath'
    scriptPath: 'scripts/create-agent.sh'
    arguments: '--model gpt-4o --name production-agent'
```

## Testing Your Agent

After creating an agent, you can test it by creating a conversation and response:

**REST API:**

```bash
# Create conversation with initial message
CONV_RESPONSE=$(curl -X POST \
  "${PROJECT_ENDPOINT}/conversations?api-version=2025-05-15-preview" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "items": [{
      "type": "message",
      "role": "user",
      "content": "Hello! Can you help me?"
    }]
  }')

CONV_ID=$(echo "$CONV_RESPONSE" | jq -r '.id')

# Create response using the agent
curl -X POST \
  "${PROJECT_ENDPOINT}/responses?api-version=2025-05-15-preview" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "conversation": "'${CONV_ID}'",
    "extra_body": {
      "agent": {
        "type": "agent_reference",
        "name": "'${AGENT_NAME}'",
        "version": "1"
      }
    }
  }'
```

## Publishing Agents to Applications

Once you've created and tested an agent, you can publish it to an application for external access:

**Via REST API:**
   ```bash
   # Update the agent deployment with agent reference
   curl -X PATCH \
     "${ENDPOINT}/api/projects/${PROJECT_NAME}/applications/${APPLICATION_NAME}/agentDeployments/${DEPLOYMENT_NAME}?api-version=2025-10-01-preview" \
     -H "Authorization: Bearer ${ACCESS_TOKEN}" \
     -H "Content-Type: application/json" \
     -d '{
       "agents": [{
         "agentName": "my-agent",
         "agentVersion": "1"
       }]
     }'
   ```

## Documentation Test History

### 2025-12-24
- Result: PASS with fixes
- Platform/Context: Windows PC with Git Bash
- OS: Windows 11 (NT-10.0-26200)
- Shell: GNU bash, version 5.2.37(1)-release (x86_64-pc-msys)
- Tester: Automated Documentation Tester
- Notes:
  - ✅ All prerequisites passed: Azure CLI authenticated, azd installed (v1.22.5), bash available
  - ✅ Infrastructure correctly provisioned: Microsoft.CognitiveServices resources found
  - ✅ Agent created successfully using **new agents API** `/agents/{name}/versions` endpoint
  - ✅ Script creates versioned agents with ID format `{name}:{version}`
  - **Fixes Applied**:
    - Changed API version from `2025-05-01` to `2025-05-15-preview` for new agents API
    - Added required `"kind": "prompt"` property to definition object
  - jq not installed but optional (script works without it)
  - **Key Finding**: New agents API requires preview API version, not GA version
