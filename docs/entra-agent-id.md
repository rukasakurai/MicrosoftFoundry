# Microsoft Entra Agent ID Guide

> ⚠️ **This document has been split into two separate guides. Please use the links below.**

## Quick Reference

| Feature | Guide | Purpose | When to Use |
|---------|-------|---------|-------------|
| **Agent Registry** | [entra-agent-registry.md](./entra-agent-registry.md) | Visibility, governance, audit trail | You want agents to appear in Entra admin center |
| **Agent Identity** | [entra-agent-identity.md](./entra-agent-identity.md) | Agent authentication, token requests | You want agents to authenticate as themselves |

These are **independent features** - choose the one that matches your needs, or use both.

## Overview

[Microsoft Entra Agent ID](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/what-is-agent-id) provides a centralized identity management system for AI agents with two main components:

### Agent Registry

Register your agents for visibility and governance. After registration, your agent will be visible in the [Microsoft Entra admin center](https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/AllAgents.MenuView/~/overview) but will show **"Has Agent ID: No"**.

👉 **See [entra-agent-registry.md](./entra-agent-registry.md) for complete instructions.**

### Agent Identity

Create verifiable identities so agents can authenticate as themselves and request tokens. After creating an Agent Identity, your agent will show **"Has Agent ID: Yes"** in the Entra admin center.

👉 **See [entra-agent-identity.md](./entra-agent-identity.md) for complete instructions.**

## Additional Resources

- [Microsoft Entra Agent ID Documentation](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/what-is-agent-id)
- [Agent Creation Guide](./agent-creation.md) - Create agents in Microsoft Foundry first
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

### Step 3: Register with Microsoft Entra Agent ID

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

### Understanding Agent Identifiers

When working with Microsoft Entra Agent ID, you'll encounter several identifiers:

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

---

## Part 2: Creating an Agent Identity

> ⚠️ **Important**: The steps in Part 1 only **register** your agent in the Agent Registry for visibility and governance. To give your agent its own identity (so it can authenticate as itself and show **"Has Agent ID: Yes"**), you need to create and assign an **Agent Identity**.

### Understanding Agent Identity Architecture

Agent Identities use a **blueprint pattern**:

| Component | Description | Purpose |
|-----------|-------------|----------|
| **Agent Identity Blueprint** | A template/factory for creating agent identities | Holds shared config, credentials, and permissions |
| **Agent Identity** | An individual identity created from a blueprint | Used by a specific agent instance to authenticate |
| **Agent Identity Blueprint Principal** | Service principal for the blueprint | Enables the blueprint to create identities |

### Prerequisites for Agent Identity

In addition to Part 1 prerequisites, you need:

1. **Agent ID Administrator** or **Agent ID Developer** role (different from Agent Registry Administrator)
2. **Additional Microsoft Graph permissions**:
   - `AgentIdentityBlueprint.Create` - Create blueprints
   - `AgentIdentityBlueprint.ReadWrite.All` - Configure blueprints
   - `AgentIdentityBlueprint.AddRemoveCreds.All` - Add credentials to blueprints

### Step 1: Authorize Your Client

Grant your app registration the required permissions:

```bash
# Get your app's object ID
APP_OBJECT_ID=$(az ad app show --id "<your-app-id>" --query id -o tsv)

# Add AgentIdentityBlueprint.Create permission
# Note: This must be done in Azure Portal > App registrations > API permissions
# Add Microsoft Graph > Application permissions > AgentIdentityBlueprint.Create
# Then grant admin consent
```

> **Note**: You also need the **Agent ID Administrator** role assigned to your service principal in Microsoft Entra admin center: **Roles and administrators** → **Agent ID Administrator** → **Add assignments**.

### Step 2: Create an Agent Identity Blueprint

```bash
# Get access token (must have AgentIdentityBlueprint.Create permission)
ACCESS_TOKEN=$(az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv)

# Get your user ID for sponsor
USER_ID=$(az ad signed-in-user show --query id -o tsv)

# Create the Agent Identity Blueprint
curl -X POST \
  "https://graph.microsoft.com/beta/applications" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "OData-Version: 4.0" \
  -d '{
    "@odata.type": "Microsoft.Graph.AgentIdentityBlueprint",
    "displayName": "MyFoundryAgent-Blueprint",
    "sponsors@odata.bind": [
      "https://graph.microsoft.com/v1.0/users/'"${USER_ID}"'"
    ],
    "owners@odata.bind": [
      "https://graph.microsoft.com/v1.0/users/'"${USER_ID}"'"
    ]
  }'
```

Save the `appId` from the response - you'll need it for the next steps.

### Step 3: Create a Blueprint Principal

```bash
# Create service principal for the blueprint
BLUEPRINT_APP_ID="<appId-from-step-2>"

curl -X POST \
  "https://graph.microsoft.com/beta/serviceprincipals/graph.agentIdentityBlueprintPrincipal" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "OData-Version: 4.0" \
  -d '{
    "appId": "'"${BLUEPRINT_APP_ID}"'"
  }'
```

### Step 4: Add Credentials to the Blueprint

For testing, add a client secret:

```bash
# Get the blueprint's object ID (different from appId)
BLUEPRINT_OBJECT_ID=$(az ad app show --id "${BLUEPRINT_APP_ID}" --query id -o tsv)

# Add a password credential
curl -X POST \
  "https://graph.microsoft.com/beta/applications/${BLUEPRINT_OBJECT_ID}/addPassword" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "passwordCredential": {
      "displayName": "Blueprint-Secret",
      "endDateTime": "2026-12-31T23:59:59Z"
    }
  }'
```

> **Security Note**: For production, use managed identities or federated credentials instead of client secrets.

### Step 5: Create an Agent Identity

Now use the blueprint to create an actual agent identity:

```bash
# First, get a token using the blueprint's credentials
BLUEPRINT_SECRET="<secret-from-step-4>"
TENANT_ID=$(az account show --query tenantId -o tsv)

# Get token for the blueprint
BLUEPRINT_TOKEN=$(curl -s -X POST \
  "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=${BLUEPRINT_APP_ID}&client_secret=${BLUEPRINT_SECRET}&scope=https://graph.microsoft.com/.default&grant_type=client_credentials" \
  | jq -r '.access_token')

# Create the agent identity
curl -X POST \
  "https://graph.microsoft.com/beta/serviceprincipals/Microsoft.Graph.AgentIdentity" \
  -H "Authorization: Bearer ${BLUEPRINT_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "OData-Version: 4.0" \
  -d '{
    "displayName": "MyFoundryAgent-Identity",
    "agentIdentityBlueprintId": "'"${BLUEPRINT_APP_ID}"'",
    "sponsors@odata.bind": [
      "https://graph.microsoft.com/v1.0/users/'"${USER_ID}"'"
    ]
  }'
```

### Step 6: Verify Agent Identity

After creating the agent identity:

1. Go to [Microsoft Entra admin center](https://entra.microsoft.com)
2. Navigate to **Agent ID (Preview)** → **All agent identities (Preview)**
3. Your agent should now appear with **"Has Agent ID: Yes"**

### Alternative: Using PowerShell

Microsoft provides a PowerShell module that simplifies this process:

```powershell
# Install the Agent ID PowerShell module
Install-Module -Name Microsoft.Graph.Beta -Scope CurrentUser

# Connect with required scopes
Connect-MgGraph -Scopes "AgentIdentityBlueprint.Create", "AgentIdentityBlueprint.ReadWrite.All"

# Follow Microsoft's documentation for PowerShell commands
# See: https://aka.ms/agentidpowershell
```

### Additional Resources for Agent Identity

- [What are Agent Identities](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/what-is-agent-id)
- [Agent Identity Blueprints](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/agent-blueprint)
- [Create Agent Identity Blueprint](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/create-blueprint)
- [Create Agent Identities](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/create-delete-agent-identities)
- [Agent ID PowerShell Module](https://aka.ms/agentidpowershell)
- [Agent ID Administrator Role](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference#agent-id-administrator)

> **Note**: The Agent Identity APIs are in preview and may change. This guide will be updated as the APIs stabilize.

---

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

**Test Commands Executed:**
1. `az version` - Azure CLI 2.76.0 ✅
2. `az account show` - Authenticated ✅
3. `az ad app create --display-name "Agent-Registry-Automation"` - App created ✅
4. `az ad app credential reset` - Client secret created ✅
5. `az ad sp create` - SP already existed (auto-created on consent) ✅
6. `az login --service-principal --allow-no-subscriptions` - Logged in as SP ✅
7. `bash register-agent-entra.sh --agent-name "doctest-agent-..."` - **SUCCESS** ✅
8. Verified in Entra admin center - Agent visible ✅

### 2025-12-24 (Fourth Test)
- Result: PARTIAL (permission blocked - as expected)
- Platform/Context: Windows workstation with Git Bash
- OS: Windows 11 (build 26200)
- Shell: GNU bash 5.2.37(1)-release (x86_64-pc-msys)
- Azure CLI: 2.76.0
- Tester: Automated Documentation Tester
- Notes:
  - All prerequisite steps validated successfully (Azure CLI installed, authenticated)
  - Script `register-agent-entra.sh` executes correctly with proper parameter handling
  - GET `/agentRegistry/agentInstances` works (returns empty list, confirming API access)
  - POST (agent registration) returns HTTP 403 as documented - this is expected behavior
  - Documentation accurately describes the permission limitation and workarounds
  - Script error handling is clear and provides actionable guidance

**Test Commands Executed:**
1. `az version` - Azure CLI 2.76.0 confirmed
2. `az account show` - Authentication verified
3. `bash register-agent-entra.sh --agent-name "doctest-agent-1766575654"` - HTTP 403 (expected)
4. `curl GET /agentRegistry/agentInstances` - Returns empty list (API accessible)

**Documentation Accuracy:**
- Prerequisites section correctly warns about Azure CLI limitation
- Custom app registration requirement is clearly documented
- Error handling in script matches documented behavior

### 2025-12-24 (Second Test)
- Result: PASS with fixes
- Platform/Context: Windows workstation with Git Bash
- OS: Windows 11 (build 26200)
- Shell: GNU bash 5.2.37(1)-release (x86_64-pc-msys)
- Tester: Automated Documentation Tester (with human intervention)
- Notes: Identified and documented that Azure CLI tokens do not include `AgentInstance.ReadWrite.All` scope. Updated documentation to clarify this limitation and recommend using Microsoft Entra admin center for manual registration or custom app registration for programmatic access.

**Key Finding:**
Azure CLI's built-in Graph token does not include `AgentInstance.ReadWrite.All` scope. Even with "Agent Registry Administrator" role assigned, the script fails with HTTP 403. Documentation updated to reflect this limitation.

**Fixes Applied:**
1. Added warning box in Prerequisites about Azure CLI limitation
2. Changed "Option 1" from Azure CLI usage to Microsoft Entra admin center (GUI)
3. Clarified that programmatic access requires custom app registration

### 2025-12-24 (Third Test)
- Result: PARTIAL (permission blocked)
- Platform/Context: Windows workstation with Git Bash
- OS: Windows 11 (build 26200)
- Shell: GNU bash 5.2.37(1)-release (x86_64-pc-msys)
- Azure CLI: 2.76.0
- Tester: Automated Documentation Tester
- Notes: 
  - Prerequisites section accurate - Azure CLI authentication works correctly
  - Script `register-agent-entra.sh` executes and handles 403 error gracefully
  - GET `/agentRegistry/agentInstances` endpoint works (returns empty list)
  - **Agent registration FAILED** - POST returned HTTP 403 due to missing `AgentInstance.ReadWrite.All` permission
  - End-to-end workflow could NOT be validated (no agent created)
  - UI navigation path updated to match actual Entra admin center: **Agent ID (Preview)** → **Agent registry (Preview)**

**Blocking Issue:**
User does not have `AgentInstance.ReadWrite.All` permission. Full workflow validation requires either:
1. Agent Registry Administrator role + custom app registration with the permission granted, OR
2. Manual registration via the Entra admin center GUI

**Test Commands Executed:**
1. `az version` - Verified Azure CLI 2.76.0 installed
2. `az account show` - Verified authentication active
3. `bash register-agent-entra.sh --agent-name "doctest-agent-1766574952"` - Script executed, **HTTP 403 - FAILED**
4. `curl GET /agentRegistry/agentInstances` - Returned empty list
5. Verified in Entra admin center UI - "0 agents found" confirms no agent was created

### 2025-12-24 (First Test)
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