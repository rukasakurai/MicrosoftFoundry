# Microsoft Entra Agent Registry Guide

This guide explains how to register AI agents in the **Microsoft Entra Agent Registry** for visibility and governance. This makes your agents discoverable and manageable in the Microsoft Entra admin center.

> **Looking for Agent Identity?** If you want your agent to authenticate as itself (get tokens, access resources), see [entra-agent-identity.md](./entra-agent-identity.md) instead.

## Overview

[Microsoft Entra Agent ID](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/what-is-agent-id) provides a centralized identity management system for AI agents.

**Agent Registry** provides:

- **Centralized visibility**: View all agents in the [Microsoft Entra admin center](https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/AllAgents.MenuView/~/overview)
- **Governance and compliance**: Apply enterprise-wide policies to AI agents
- **Audit trail**: Track agent activities and ownership

> **Note**: Registering an agent in the registry does **not** give it authentication capabilities. After registration, your agent will show **"Has Agent ID: No"** in Entra admin center. To enable agent authentication, see [entra-agent-identity.md](./entra-agent-identity.md).

## Prerequisites

Before registering agents with Microsoft Entra Agent Registry, ensure you have:

1. **Azure CLI** installed and authenticated (`az login`)
2. **Microsoft Entra permissions**:
   - Agent Registry Administrator role (minimum required)
   - Or a custom role with equivalent permissions
3. **Microsoft Graph API permissions** (for programmatic access):
   - `AgentInstance.ReadWrite.All` (Application or Delegated)
4. **Admin consent capability** (one of the following):
   - **Global Administrator** or **Privileged Role Administrator** role to grant admin consent yourself, OR
   - Access to a tenant admin who can grant consent on your behalf
5. **A deployed Microsoft Foundry agent** (see [agent-creation.md](./agent-creation.md))

> ⚠️ **Important**: The Azure CLI's built-in Microsoft Graph permissions do **not** include `AgentInstance.ReadWrite.All`. Even with the Agent Registry Administrator role, you cannot register agents using Azure CLI tokens directly. You must create a **custom app registration** with `AgentInstance.ReadWrite.All` permission granted and authenticate as that app. See [Setting Up Permissions](#setting-up-permissions) below.

## Quick Start

### Register an Agent Using the Script

After creating an agent in Microsoft Foundry, register it with Microsoft Entra Agent Registry:

```bash
# Navigate to the scripts directory
cd scripts

# Register the agent
./register-agent-entra.sh --agent-name "foundry-agent" --display-name "My Foundry Agent"
```

### Verify Registration

After registration, verify your agent appears in the Microsoft Entra admin center:

1. Navigate to [Microsoft Entra admin center](https://entra.microsoft.com)
2. In the left sidebar, click **Agent ID (Preview)** → **Agent registry (Preview)**
3. Use the "Search by name or ID" box to find your agent:
   - Search by **Name**: The `--display-name` you provided (e.g., "My Foundry Agent")
   - Search by **Registry ID**: The ID returned by the API after successful registration
4. You can also use **Add filters** to filter by originating store or other criteria

> **Tip**: The script outputs the Agent Instance ID (Registry ID) upon successful registration. Save this ID for future API operations (update, delete, etc.).

> **Note**: If you see "0 agents found" / "No data", registration may have failed (check for HTTP 403 permission errors).

## Detailed Setup

### Setting Up Permissions

To register agents programmatically, you need an app registration with the `AgentInstance.ReadWrite.All` Microsoft Graph API permission. Azure CLI user tokens do not include this scope.

#### Create an App Registration with Required Permissions

1. **Create an App Registration** in Microsoft Entra:
   ```bash
   az ad app create --display-name "Agent-Registry-Automation"
   ```
   Save the `appId` from the output.

2. **Add API Permission** for Microsoft Graph:
   - Go to [Azure Portal](https://portal.azure.com) → Microsoft Entra ID → App registrations
   - Select your app → API permissions → Add a permission
   - Choose **Microsoft Graph** → **Application permissions**
   - Search for and add `AgentInstance.ReadWrite.All`
   - Click **"Grant admin consent for [your tenant]"**
   
   > ⚠️ **Note**: The "Grant admin consent" button requires **Global Administrator** or **Privileged Role Administrator** role. If the button is grayed out, contact your tenant admin to grant consent.

3. **Create a Client Secret**:
   ```bash
   APP_ID="<your-app-id>"
   az ad app credential reset --id $APP_ID --append --display-name "agent-registry-secret"
   ```
   **Save the `password` value** - this is your client secret and won't be shown again.

4. **Create a Service Principal**:
   ```bash
   az ad sp create --id $APP_ID
   ```

5. **Assign Agent Registry Administrator Role**:
   - Go to [Microsoft Entra admin center](https://entra.microsoft.com)
   - Navigate to: **Roles and administrators** → **Agent Registry Administrator** → **Add assignments**
   - Add your app's service principal

#### Authenticate as the App Registration

Before running the registration script, authenticate as the app (not your user account):

```bash
# Set your app credentials
APP_ID="<your-app-id>"
CLIENT_SECRET="<your-client-secret>"
TENANT_ID="<your-tenant-id>"

# Login as the service principal
# Note: --allow-no-subscriptions is required since this SP only needs Graph access, not Azure subscriptions
az login --service-principal -u $APP_ID -p $CLIENT_SECRET --tenant $TENANT_ID --allow-no-subscriptions

# Verify you're logged in as the app
az account show
```

Now the script will use the app's token which includes `AgentInstance.ReadWrite.All`.

> **Security Note**: For CI/CD, store the client secret in a secure secret store (GitHub Secrets, Azure Key Vault, etc.). Never commit secrets to source control.

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

### Step 3: Register with Microsoft Entra Agent Registry

```bash
# Register the agent with Microsoft Entra
./scripts/register-agent-entra.sh \
  --agent-name customer-assistant \
  --display-name "Customer Service Assistant"
```

### Step 4: Verify Registration

1. Open [Microsoft Entra admin center](https://entra.microsoft.com)
2. In the left sidebar, click **Agent ID (Preview)** → **Agent registry (Preview)**
3. Search for your agent by name or Registry ID
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
      
      - name: Register with Microsoft Entra Agent Registry
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

### Understanding Agent Identifiers

When working with Microsoft Entra Agent Registry, you'll encounter several identifiers:

| Identifier | Description | Where to Find It |
|------------|-------------|------------------|
| **Display Name** | Human-readable name you provide | `--display-name` parameter, Entra admin center UI |
| **Agent Instance ID** | Unique ID assigned by Microsoft Graph API | API response after registration, Entra admin center details |
| **Owner ID** | Microsoft Entra object ID of the agent owner | `az ad signed-in-user show --query id -o tsv` |
| **Originating Store** | Platform that created the agent | Defaults to "MicrosoftFoundry", visible in Entra admin center |

> **To find your agent in Entra admin center**: Search by **Display Name** or filter the list by **Originating Store** = "MicrosoftFoundry".

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

## Next Steps

- **Enable agent authentication**: See [entra-agent-identity.md](./entra-agent-identity.md) to give your agent its own credentials
- **Create more agents**: See [agent-creation.md](./agent-creation.md) for creating agents in Microsoft Foundry

## Documentation Test History

### 2025-12-24 (Fifth Test)
- Result: PASS with fixes
- Platform/Context: Windows workstation with Git Bash
- OS: Windows 11 (build 26200)
- Shell: GNU bash 5.2.37(1)-release (x86_64-pc-msys)
- Azure CLI: 2.76.0
- Tester: Automated Documentation Tester (with human intervention)
- Notes:
  - **END-TO-END SUCCESS**: Agent successfully registered and visible in Entra admin center
  - Agent Instance ID: `544aa946-36cd-415c-9172-4ca46398567e`
  - Agent appears in Agent Registry with "Created in: MicrosoftFoundry"

**Manual Steps Required (by user):**
1. Added `AgentInstance.ReadWrite.All` permission in Azure Portal (GUI)
2. Granted admin consent (required Global Admin login)
3. Assigned Agent Registry Administrator role to service principal (GUI)
4. Verified agent in Entra admin center (GUI)

**Documentation Fixes Applied:**
1. Added prerequisite #4: Admin consent capability requirement (Global Admin or Privileged Role Admin)
2. Added warning note under "Add API Permission" explaining grayed-out consent button
3. Added `--allow-no-subscriptions` flag to `az login` command for service principals without Azure subscription access
