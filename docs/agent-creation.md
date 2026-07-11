# Programmatically Creating a Prompt Agent in Microsoft Foundry

This guide explains how to programmatically create a Foundry Agent Service `prompt agent` after provisioning the project infrastructure with Bicep.

## Overview

The `prompt agent` created here is defined by configuration—model, instructions, and tools—and run by Agent Service. It does not deploy application code or create a `hosted agent`.

The Bicep template provisions the account, project, and model deployment. The script then creates the versioned `prompt agent` through the data-plane `/agents/{name}/versions` API with `definition.kind` set to `prompt`.

See [Agent Terminology](../AGENTS.md#agent-terminology) for the boundaries between prompt, hosted, custom, and external agents. This guide uses the REST API with Bash and Azure CLI.

## Prerequisites

- Microsoft Foundry infrastructure deployed (see [azd-deployment.md](./azd-deployment.md))
- Azure CLI installed and authenticated: `az login`
- Model deployments available in your Microsoft Foundry (Azure AI Services) account. `azd up` deploys one by default (`gpt-5.4`, exposed as the `MODEL_DEPLOYMENT_NAME` output); override with the `modelDeploymentName`/`modelName`/`modelVersion` parameters.
- Bash shell:
  - **Linux/macOS**: Use the default terminal
  - **Windows**: Use [Git Bash](https://git-scm.com/downloads) (included with Git for Windows)
- `jq` (optional, for better JSON formatting)

> **API version**: This guide targets the stable **`v1`** API surface. Data-plane
> calls (`/agents`, `/conversations`) use `?api-version=v1`, and the run step uses
> the path-versioned `/openai/v1/responses` endpoint (no `api-version` query). Earlier
> previews such as `2025-05-15-preview` no longer serve the run step — `POST /responses?api-version=2025-05-15-preview` returns HTTP 404.

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

After creating the `prompt agent`, verify it by listing agents or retrieving its version:

### List All Agents

```bash
# Set environment variables
eval $(azd env get-values)

# Get access token
ACCESS_TOKEN=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)

# List all agents in the project
curl -X GET \
  "${PROJECT_ENDPOINT}/agents?api-version=v1" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json"
```

### Get Specific Agent Version

```bash
# Replace with agent name and version from create-agent.sh
AGENT_NAME="foundry-agent"
AGENT_VERSION="1"

curl -X GET \
  "${PROJECT_ENDPOINT}/agents/${AGENT_NAME}/versions/${AGENT_VERSION}?api-version=v1" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json"
```

The response will include all agent properties including name, model, instructions, and configuration.

## Agent Configuration Options

When creating this `prompt agent`, you can configure these properties:

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `model` | string | Yes | Model deployment ID (e.g., "gpt-5.4", "gpt-4o") |
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

Prompt agents support several built-in tools:

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
            --model gpt-5.4 \
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
    arguments: '--model gpt-5.4 --name production-agent'
```

## Testing the Prompt Agent

After creating the `prompt agent`, test it by creating a conversation and response:

**REST API:**

```bash
# Create conversation with initial message
CONV_RESPONSE=$(curl -X POST \
  "${PROJECT_ENDPOINT}/conversations?api-version=v1" \
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
  "${PROJECT_ENDPOINT}/openai/v1/responses" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "conversation": "'${CONV_ID}'",
    "agent_reference": {
      "type": "agent_reference",
      "name": "'${AGENT_NAME}'",
      "version": "1"
    }
  }'
```

## Publishing the Prompt Agent

Once you've created and tested the `prompt agent`, you can publish it so external consumers can call it through a stable endpoint. Publishing creates the underlying **application** and **agent-deployment** resources for you (they are not provisioned by this template):

- **Foundry portal**: open the agent in the Agent Builder and select **Publish Agent**.
- **REST API**: use the [agent publishing API](https://learn.microsoft.com/en-us/azure/foundry/agents/how-to/migrate-agent-applications) to create/update an application and its deployment with the target `agentName`/`agentVersion`.

## Documentation Test History

### 2026-07-06
- Result: PASS
- Platform/Context: WSL (Ubuntu), Azure CLI + azd, throwaway `azd` environment (`japaneast`)
- Tester: Automated E2E (see `.github/skills/e2e-foundry-baseline`)
- Notes:
  - Migrated the flow to the stable **`v1`** API surface (see #24). Data-plane calls
    (`/agents`, `/conversations`) use `?api-version=v1`; the run step uses
    `/openai/v1/responses`.
  - ✅ Confirmed `POST /responses?api-version=2025-05-15-preview` now returns **HTTP 404**
    (the break this change fixes).
  - ✅ `scripts/create-agent.sh` (now `API_VERSION=v1`) created `guide-agent:1`.
  - ✅ Two-step run flow (create conversation → `POST /openai/v1/responses` with a
    top-level `agent_reference`) returned **HTTP 200** and the agent's reply.
  - Note: the run body uses top-level `agent_reference`, not the previous
    `extra_body.agent` shape (which returns "Missing required parameter: 'model'").

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
