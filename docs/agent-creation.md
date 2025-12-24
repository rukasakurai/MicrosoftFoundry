# Programmatically Creating Agents in Microsoft Foundry

This guide explains how to programmatically create AI agents in your Microsoft Foundry project after provisioning infrastructure with Bicep templates.

## Overview

Microsoft Foundry agents are intelligent assistants powered by large language models (LLMs) that can be configured with custom instructions, tools, and capabilities. While the Bicep templates provision the infrastructure (AI Services, Projects, Applications, and Deployments), the actual agent logic must be created separately.

While various approaches exist, this repository focuses on programmatic agent creation with **REST API with Bash/Azure CLI**

## Prerequisites

- Microsoft Foundry infrastructure deployed (see [azd-deployment.md](./azd-deployment.md))
- Azure CLI installed and authenticated: `az login`
- Model deployments available in your Azure OpenAI service or Azure AI Services
- Bash shell:
  - **Linux/macOS**: Use the default terminal
  - **Windows**: Use [Git Bash](https://git-scm.com/downloads) (included with Git for Windows)
- `jq` (optional, for better JSON formatting)

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
  "${PROJECT_ENDPOINT}/assistants?api-version=2025-05-01" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json"
```

### Get Specific Agent Details

```bash
# Replace AGENT_ID with the ID returned from create-agent.sh
AGENT_ID="asst_xxxxxxxxxxxxx"

curl -X GET \
  "${PROJECT_ENDPOINT}/assistants/${AGENT_ID}?api-version=2025-05-01" \
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

After creating an agent, you can test it by creating a conversation thread:

**REST API:**

```bash
# Create thread
THREAD_RESPONSE=$(curl -X POST \
  "${AZURE_AI_FOUNDRY_PROJECT_ENDPOINT}/threads?api-version=2025-05-01" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json")

THREAD_ID=$(echo "$THREAD_RESPONSE" | jq -r '.id')

# Add message
curl -X POST \
  "${AZURE_AI_FOUNDRY_PROJECT_ENDPOINT}/threads/${THREAD_ID}/messages?api-version=2025-05-01" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "role": "user",
    "content": "Hello! Can you help me?"
  }'

# Run the agent
curl -X POST \
  "${AZURE_AI_FOUNDRY_PROJECT_ENDPOINT}/threads/${THREAD_ID}/runs?api-version=2025-05-01" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"assistant_id": "'${AGENT_ID}'"}'
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

### 2024-12-24
- Result: PASS with manual steps and fixes
- Platform/Context: Windows PC with Git Bash
- OS: Windows 11 (NT-10.0-26200)
- Shell: GNU bash version 5.2.37(1)-release (MINGW64)
- Tester: Automated Documentation Tester (with human intervention)
- Notes: 
  - Manual step required: Azure CLI authentication (`az login`)
  - Manual step required: User confirmation to create Azure resources
  - Fixed Quick Start example: Changed to use `&&` to chain commands so environment variables persist in bash
  - Successfully created test agents using both default and custom parameters
  - jq not required but recommended (script works without it)
  - API version 2025-05-01 confirmed as current and working
