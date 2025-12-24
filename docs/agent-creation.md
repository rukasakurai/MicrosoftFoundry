# Programmatically Creating Agents in Microsoft Foundry

This guide explains how to programmatically create AI agents in your Microsoft Foundry project after provisioning infrastructure with Bicep templates.

## Overview

Microsoft Foundry agents are intelligent assistants powered by large language models (LLMs) that can be configured with custom instructions, tools, and capabilities. While the Bicep templates provision the infrastructure (AI Services, Projects, Applications, and Deployments), the actual agent logic must be created separately.

While various approaches exist, this repository focuses on programmatic agent creation with **REST API with Bash/Azure CLI**

> **Migration Note (December 2025):** Microsoft has introduced a new agents developer experience with updated API concepts. Key terminology changes:
> - **Threads → Conversations**: Conversations now support streams of items (messages, tool calls, outputs) for richer context management
> - **Runs → Responses**: The Responses API provides more sophisticated agent-to-agent and tool workflow orchestration
> - **Messages → Items**: Items can include messages, tool calls, and outputs for more flexible data handling
>
> The existing `/assistants` API remains supported for backward compatibility. See Microsoft's [Migration Guide](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/migrate?view=foundry) for details.

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

After creating an agent, you can test it by creating a conversation. The new Responses API provides enhanced capabilities, though the legacy threads API remains supported for backward compatibility.

### Using the New Conversations/Responses API (Recommended)

The new API uses conversations (replacing threads) and responses (replacing runs) for improved context management:

**REST API:**

```bash
# Create a conversation with initial message
CONVERSATION_RESPONSE=$(curl -X POST \
  "${PROJECT_ENDPOINT}/conversations?api-version=2025-05-01" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "items": [
      {
        "type": "message",
        "role": "user",
        "content": "Hello! Can you help me?"
      }
    ],
    "metadata": {
      "agent": "'${AGENT_ID}'"
    }
  }')

CONVERSATION_ID=$(echo "$CONVERSATION_RESPONSE" | jq -r '.id')

# Get a response from the agent
RESPONSE=$(curl -X POST \
  "${PROJECT_ENDPOINT}/responses?api-version=2025-05-01" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "conversation_id": "'${CONVERSATION_ID}'",
    "input_items": [
      {
        "type": "message",
        "role": "user",
        "content": "What can you do?"
      }
    ]
  }')

echo "$RESPONSE" | jq '.output_items'
```

### Using the Legacy Threads API (Backward Compatible)

The threads API is still supported for existing implementations:

**REST API:**

```bash
# Create thread
THREAD_RESPONSE=$(curl -X POST \
  "${PROJECT_ENDPOINT}/threads?api-version=2025-05-01" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json")

THREAD_ID=$(echo "$THREAD_RESPONSE" | jq -r '.id')

# Add message
curl -X POST \
  "${PROJECT_ENDPOINT}/threads/${THREAD_ID}/messages?api-version=2025-05-01" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "role": "user",
    "content": "Hello! Can you help me?"
  }'

# Run the agent
curl -X POST \
  "${PROJECT_ENDPOINT}/threads/${THREAD_ID}/runs?api-version=2025-05-01" \
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

## Migration Guide

If you're migrating from the legacy Assistants API to the new Agents developer experience, here's a summary of the key changes:

| Legacy Concept | New Concept | Description |
|---------------|-------------|-------------|
| Thread | Conversation | Persistent context that stores streams of items, not just messages |
| Run | Response | Explicit tool call management with input/output items |
| Message | Item | Items include messages, tool calls, and outputs |
| Classic Agent | New Agent | Supports prompt-based, workflow-based, or container-based agents |

### Migration Benefits

- **Enhanced Enterprise Features**: Single-tenant storage, bring-your-own Cosmos DB for agent/conversation state
- **Multi-Agent Workflows**: Build and chain multiple agents for complex orchestration
- **Stateful Context**: Conversations retain context across calls by default
- **Improved Security**: Granular RBAC controls and audit trails
- **Expanded Model Support**: Access to latest models including GPT-5 and other providers

### Resources

- [Microsoft Migration Guide](https://learn.microsoft.com/en-us/azure/ai-foundry/agents/how-to/migrate?view=foundry)
- [Azure AI Foundry Agent Service REST API](https://learn.microsoft.com/en-us/rest/api/aifoundry/aiagents/)
- [Responses API Documentation](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/how-to/responses?view=foundry-classic)

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
