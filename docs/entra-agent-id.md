# Microsoft Entra Agent ID Registration Guide

This guide explains how to register AI agents created in this repository with Microsoft Entra Agent ID, making them visible and manageable in the Microsoft Entra admin center.

## Overview

[Microsoft Entra Agent ID](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/what-is-agent-id) provides a centralized identity management system for AI agents. By registering your agents with the Agent Registry, you enable:

- **Centralized visibility**: View all agents in the [Microsoft Entra admin center](https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/AllAgents.MenuView/~/overview)
- **Governance and compliance**: Apply enterprise-wide policies to AI agents
- **Identity management**: Assign verifiable identities to agents
- **Access control**: Configure Conditional Access and Identity Protection for agents
- **Audit trail**: Track agent activities and ownership

## Prerequisites

Before registering agents with Microsoft Entra Agent ID, ensure you have:

1. **Azure CLI** installed and authenticated (`az login`)
2. **Microsoft Entra permissions**:
   - Agent Registry Administrator role (minimum required)
   - Or a custom role with equivalent permissions
3. **Microsoft Graph API permissions** (for programmatic access):
   - `AgentInstance.ReadWrite.All` (Application or Delegated)
4. **A deployed Microsoft Foundry agent** (see [agent-creation.md](./agent-creation.md))

## Quick Start

### Register an Agent Using the Script

After creating an agent in Microsoft Foundry, register it with Microsoft Entra Agent ID:

```bash
# Navigate to the scripts directory
cd scripts

# Register the agent
./register-agent-entra.sh --agent-name "foundry-agent" --display-name "My Foundry Agent"
```

### Verify Registration

After registration, verify your agent appears in the Microsoft Entra admin center:
1. Navigate to [Microsoft Entra admin center](https://entra.microsoft.com)
2. Go to **Applications** → **Enterprise applications**
3. Filter by **Application type: Agent ID (Preview)**
4. Your agent should appear in the list

## Detailed Setup

### Setting Up Permissions

To register agents programmatically, you need the appropriate Microsoft Graph API permissions.

#### Option 1: Using Your User Account (Delegated Permissions)

If you have the Agent Registry Administrator role:

```bash
# Simply run the registration script - it will use your Azure CLI credentials
./scripts/register-agent-entra.sh --agent-name "my-agent"
```

#### Option 2: Using an App Registration (Application Permissions)

For CI/CD pipelines or automation, create an app registration with the required permissions:

1. **Create an App Registration** in Microsoft Entra:
   ```bash
   az ad app create --display-name "Agent-Registry-Automation"
   ```

2. **Add API Permission** for Microsoft Graph:
   - Go to Azure Portal → Microsoft Entra ID → App registrations
   - Select your app → API permissions → Add a permission
   - Choose Microsoft Graph → Application permissions
   - Search for and add `AgentInstance.ReadWrite.All`
   - Click "Grant admin consent"

3. **Create a Service Principal**:
   ```bash
   APP_ID="<your-app-id>"
   az ad sp create --id $APP_ID
   ```

4. **Assign Agent Registry Administrator Role**:
   ```bash
   SP_OBJECT_ID=$(az ad sp show --id $APP_ID --query id -o tsv)
   # The role assignment for Agent Registry Administrator is done in Entra admin center
   # Navigate to: Roles and administrators → Agent Registry Administrator → Add assignments
   ```

### Registering Agents

#### Using the Bash Script

The `register-agent-entra.sh` script provides a straightforward way to register agents:

```bash
# Basic registration
./scripts/register-agent-entra.sh --agent-name "foundry-agent"

# Full customization
./scripts/register-agent-entra.sh \
  --agent-name "customer-service-agent" \
  --display-name "Customer Service AI Agent" \
  --agent-url "https://myproject.services.ai.azure.com/api/agents/customer-service" \
  --description "Automated customer service agent for support inquiries"
```

**Available Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| `--agent-name` | Yes | Unique identifier for the agent |
| `--display-name` | No | Human-readable name (defaults to agent-name) |
| `--agent-url` | No | Operational endpoint URL for the agent |
| `--owner-id` | No | Owner's Microsoft Entra object ID (defaults to current user) |
| `--description` | No | Description of the agent's purpose |
| `--originating-store` | No | Platform name (defaults to "MicrosoftFoundry") |

#### Using the REST API Directly

You can also register agents directly using the Microsoft Graph API:

```bash
# Get access token
ACCESS_TOKEN=$(az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv)

# Get your user object ID (for ownerIds)
OWNER_ID=$(az ad signed-in-user show --query id -o tsv)

# Register the agent
curl -X POST \
  "https://graph.microsoft.com/beta/agentRegistry/agentInstances" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "My Foundry Agent",
    "ownerIds": ["'"${OWNER_ID}"'"],
    "url": "https://myproject.services.ai.azure.com/api/agents/my-agent",
    "originatingStore": "MicrosoftFoundry"
  }'
```

## Complete Workflow

Here's the recommended workflow for creating and registering an agent:

### Step 1: Deploy Infrastructure

```bash
# Deploy Microsoft Foundry infrastructure
azd up
```

### Step 2: Create an Agent

```bash
# Load environment variables
eval $(azd env get-values)

# Create the agent in Microsoft Foundry
./scripts/create-agent.sh \
  --name customer-assistant \
  --instructions "You are a helpful customer service assistant."
```

### Step 3: Register with Microsoft Entra Agent ID

```bash
# Register the agent with Microsoft Entra
./scripts/register-agent-entra.sh \
  --agent-name customer-assistant \
  --display-name "Customer Service Assistant"
```

### Step 4: Verify Registration

1. Open [Microsoft Entra admin center](https://entra.microsoft.com)
2. Navigate to **Applications** → **Enterprise applications**
3. Filter by **Application type: Agent ID (Preview)**
4. Confirm your agent appears in the list

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Deploy and Register Agent

on:
  push:
    branches: [main]

jobs:
  deploy-agent:
    runs-on: ubuntu-latest
    permissions:
      id-token: write
      contents: read
    
    steps:
      - uses: actions/checkout@v4
      
      - name: Azure Login (OIDC)
        uses: azure/login@v2
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
      
      - name: Install azd
        run: curl -fsSL https://aka.ms/install-azd.sh | bash
      
      - name: Get Environment Variables
        run: |
          eval $(azd env get-values)
          echo "PROJECT_ENDPOINT=${PROJECT_ENDPOINT}" >> $GITHUB_ENV
          echo "PROJECT_NAME=${PROJECT_NAME}" >> $GITHUB_ENV
      
      - name: Create Agent
        run: |
          ./scripts/create-agent.sh \
            --name production-agent \
            --instructions "$(cat agent-config/instructions.txt)"
      
      - name: Register with Microsoft Entra Agent ID
        run: |
          ./scripts/register-agent-entra.sh \
            --agent-name production-agent \
            --display-name "Production AI Agent"
```

## Managing Registered Agents

### List All Registered Agents

```bash
ACCESS_TOKEN=$(az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv)

curl -X GET \
  "https://graph.microsoft.com/beta/agentRegistry/agentInstances" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json"
```

### Get a Specific Agent Instance

```bash
INSTANCE_ID="<agent-instance-id>"

curl -X GET \
  "https://graph.microsoft.com/beta/agentRegistry/agentInstances/${INSTANCE_ID}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json"
```

### Update an Agent Instance

```bash
INSTANCE_ID="<agent-instance-id>"

curl -X PATCH \
  "https://graph.microsoft.com/beta/agentRegistry/agentInstances/${INSTANCE_ID}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "displayName": "Updated Agent Name"
  }'
```

### Delete an Agent Instance

```bash
INSTANCE_ID="<agent-instance-id>"

curl -X DELETE \
  "https://graph.microsoft.com/beta/agentRegistry/agentInstances/${INSTANCE_ID}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"
```

## Common Issues

### "Authorization failed" or "Access denied"

**Cause**: Missing permissions or role assignments.

**Solution**:
1. Verify you have the Agent Registry Administrator role in Microsoft Entra
2. If using an app registration, ensure `AgentInstance.ReadWrite.All` permission is granted
3. Ensure admin consent has been granted for the permission

### "Invalid request" or "Bad request"

**Cause**: Missing required fields or invalid JSON format.

**Solution**:
1. Ensure `displayName` is provided (required field)
2. If providing `ownerIds`, ensure it's a valid array of Microsoft Entra object IDs
3. Check JSON formatting in the request body

### Agent not appearing in Entra admin center

**Cause**: Registration succeeded but agent isn't visible.

**Solution**:
1. Wait a few minutes for propagation
2. Ensure you're filtering by "Agent ID (Preview)" application type
3. Verify the agent was created successfully (check API response)

## Additional Resources

- [Microsoft Entra Agent ID Documentation](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/what-is-agent-id)
- [Register Agents to the Agent Registry](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/publish-agents-to-registry)
- [Microsoft Graph API - agentInstances](https://learn.microsoft.com/en-us/graph/api/agentregistry-post-agentinstances?view=graph-rest-beta)
- [Agent Registry Administrator Role](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference#agent-registry-administrator)

## API Version Note

> **API Version (as of December 2025)**: The Agent Registry API is available only in the Microsoft Graph beta endpoint (`https://graph.microsoft.com/beta/`). This API may change before reaching general availability. Monitor the [Microsoft Graph changelog](https://learn.microsoft.com/en-us/graph/changelog) for updates.

## Documentation Test History

### 2025-12-24
- Result: PARTIAL
- Platform/Context: Windows workstation with Git Bash
- OS: Windows 11 (build 26200)
- Shell: GNU bash 5.2.37(1)-release (x86_64-pc-msys)
- Tester: Automated Documentation Tester (with human intervention)
- Notes: Agent registration blocked by missing "Agent Registry Administrator" role (403 error), which correctly validates the documented prerequisites.

**Test Command:**
```bash
cd scripts && bash register-agent-entra.sh --agent-name "doctest-agent-rusakura-1766570018" --display-name "Documentation Test Agent Rusakura"
```

**Error Output:**
```
✗ Error: Failed to register agent (HTTP 403)

Authentication/Authorization Error

This error typically occurs when:
  1. The signed-in user doesn't have 'Agent Registry Administrator' role
  2. The app/user doesn't have 'AgentInstance.ReadWrite.All' permission
  3. Admin consent hasn't been granted for the required permissions

To resolve:
  1. Ensure you have the Agent Registry Administrator role in Microsoft Entra
  2. If using an app registration, grant AgentInstance.ReadWrite.All permission
  3. Have an admin grant consent for the permissions

Response:
{"error":{"code":"UnknownError","message":"","innerError":{"date":"2025-12-24T09:53:47","request-id":"x","client-request-id":"x"}}}
```