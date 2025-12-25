# Microsoft Entra Agent Identity Guide

This guide explains how to create **Agent Identities** in Microsoft Entra, allowing your AI agents to authenticate as themselves, request tokens, and access resources.

> **Looking for Agent Registry?** If you only want to make your agents visible in the Entra admin center (for governance/visibility), see [entra-agent-registry.md](./entra-agent-registry.md) instead. Agent Registry and Agent Identity are independent features.

## Overview

[Microsoft Entra Agent ID](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/what-is-agent-id) provides a centralized identity management system for AI agents.

**Agent Identity** provides:

- **Identity management**: Assign verifiable identities to agents
- **Access control**: Configure Conditional Access and Identity Protection for agents
- **Agent authentication**: Allow agents to request tokens and authenticate as themselves
- **Delegated access**: Agents can act on behalf of users with proper consent

## 0. Prerequisites

Before creating Agent Identities, ensure you have:

1. **Azure CLI** installed and authenticated (`az login`)
2. **Microsoft Entra roles** (one of the following):
   - **Agent ID Administrator** (recommended)
   - **Agent ID Developer**
3. **Microsoft Graph API permissions**:
   - `AgentIdentityBlueprint.Create` - Create blueprints
   - `AgentIdentityBlueprint.ReadWrite.All` - Configure blueprints
   - `AgentIdentityBlueprint.AddRemoveCreds.All` - Add credentials to blueprints
4. **Admin consent capability**:
   - **Global Administrator** or **Privileged Role Administrator** role to grant admin consent yourself, OR
   - Access to a tenant admin who can grant consent on your behalf

> ⚠️ **Important**: The Azure CLI's built-in Microsoft Graph permissions do **not** include `AgentIdentityBlueprint.*` scopes. You must create a **custom app registration** with these permissions granted and authenticate as that app.

## 1. Setting Up Permissions

### Step 1: Create an App Registration

```bash
# Create an app registration for Agent Identity management
az ad app create --display-name "Agent-Identity-Automation"
```

Save the `appId` from the output.

### Step 2: Add API Permissions (GUI Required)

1. Go to [Azure Portal](https://portal.azure.com) → Microsoft Entra ID → App registrations
2. Select your app → API permissions → Add a permission
3. Choose **Microsoft Graph** → **Application permissions**
4. Add these permissions:
   - `AgentIdentityBlueprint.Create`
   - `AgentIdentityBlueprint.ReadWrite.All`
   - `AgentIdentityBlueprint.AddRemoveCreds.All`
5. Click **"Grant admin consent for [your tenant]"**

> ⚠️ **Note**: The "Grant admin consent" button requires **Global Administrator** or **Privileged Role Administrator** role. If the button is grayed out, contact your tenant admin to grant consent.

### Step 3: Create a Client Secret

```bash
APP_ID="<your-app-id>"
az ad app credential reset --id $APP_ID --append --display-name "agent-identity-secret"
```

**Save the `password` value** - this is your client secret and won't be shown again.

### Step 4: Create a Service Principal

```bash
az ad sp create --id $APP_ID
```

### Step 5: Assign Agent ID Administrator Role (GUI Required)

1. Go to [Microsoft Entra admin center](https://entra.microsoft.com)
2. Navigate to: **Roles and administrators** → **Agent ID Administrator** → **Add assignments**
3. Add your app's service principal

### Step 6: Authenticate as the App

```bash
APP_ID="<your-app-id>"
CLIENT_SECRET="<your-client-secret>"
TENANT_ID="<your-tenant-id>"

# Login as the service principal
az login --service-principal -u $APP_ID -p $CLIENT_SECRET --tenant $TENANT_ID --allow-no-subscriptions

# Verify authentication
az account show
```

## 2. Creating an Agent Identity

### Step 1: Get Access Token and User ID

```bash
# Get access token
ACCESS_TOKEN=$(az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv)

# Get your user ID for sponsor (if logged in as user)
# Note: This will fail if logged in as service principal - provide USER_ID manually
USER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || echo "<your-user-object-id>")

# If USER_ID is empty, you need to provide it manually
echo "USER_ID: $USER_ID"
```

### Step 2: Create an Agent Identity Blueprint

```bash
# Create the Agent Identity Blueprint
BLUEPRINT_RESPONSE=$(curl -s -X POST \
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
  }')

echo "$BLUEPRINT_RESPONSE" | jq '.'

# Extract the appId for next steps
BLUEPRINT_APP_ID=$(echo "$BLUEPRINT_RESPONSE" | jq -r '.appId')
BLUEPRINT_OBJECT_ID=$(echo "$BLUEPRINT_RESPONSE" | jq -r '.id')

echo "Blueprint App ID: $BLUEPRINT_APP_ID"
echo "Blueprint Object ID: $BLUEPRINT_OBJECT_ID"
```

### Step 3: Create a Blueprint Principal

```bash
# Create service principal for the blueprint
curl -s -X POST \
  "https://graph.microsoft.com/beta/serviceprincipals/graph.agentIdentityBlueprintPrincipal" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -H "OData-Version: 4.0" \
  -d '{
    "appId": "'"${BLUEPRINT_APP_ID}"'"
  }' | jq '.'
```

### Step 4: Add Credentials to the Blueprint

```bash
# Add a password credential to the blueprint
CRED_RESPONSE=$(curl -s -X POST \
  "https://graph.microsoft.com/beta/applications/${BLUEPRINT_OBJECT_ID}/addPassword" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "passwordCredential": {
      "displayName": "Blueprint-Secret",
      "endDateTime": "2026-12-31T23:59:59Z"
    }
  }')

echo "$CRED_RESPONSE" | jq '.'

# Extract the secret
BLUEPRINT_SECRET=$(echo "$CRED_RESPONSE" | jq -r '.secretText')
echo "Blueprint Secret: $BLUEPRINT_SECRET"
echo "⚠️ SAVE THIS SECRET - it won't be shown again!"
```

> **Security Note**: For production, use managed identities or federated credentials instead of client secrets. See [Microsoft documentation on credentials for agent identities](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/agent-identities#credentials-for-agent-identities).

### Step 5: Create an Agent Identity

Now use the blueprint to create an actual agent identity:

```bash
# Get tenant ID
TENANT_ID=$(az account show --query tenantId -o tsv)

# Get token for the blueprint
BLUEPRINT_TOKEN=$(curl -s -X POST \
  "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=${BLUEPRINT_APP_ID}&client_secret=${BLUEPRINT_SECRET}&scope=https://graph.microsoft.com/.default&grant_type=client_credentials" \
  | jq -r '.access_token')

# Create the agent identity
curl -s -X POST \
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
  }' | jq '.'
```

### Step 6: Verify Agent Identity

After creating the agent identity, verify it was created successfully:

#### Option A: Verify via API

```bash
# List all agent identities in your tenant
curl -s -X GET \
  "https://graph.microsoft.com/beta/serviceprincipals?\$filter=servicePrincipalType eq 'ServiceIdentity'" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | jq '.value[] | {displayName, id, agentIdentityBlueprintId}'
```

#### Option B: Verify in Entra Admin Center

1. Go to [Microsoft Entra admin center](https://entra.microsoft.com)
2. In the left navigation, expand **Agent ID (Preview)**
3. Click **All agent identities (Preview)**
4. Your agent should appear in the list with:
   - **Display name**: `MyFoundryAgent-Identity`
   - **Service principal type**: `ServiceIdentity`
   - **Blueprint ID**: The ID of your Agent Identity Blueprint
5. Click on your agent to view detailed properties including:
   - Object ID
   - Sponsors
   - Created date
   - Associated blueprint

> **Tip**: If you also registered the agent in the Agent Registry (see [entra-agent-registry.md](./entra-agent-registry.md)), the agent will show **"Has Agent ID: Yes"** in the registry view.

## 3. Using the Agent Identity

Once created, your agent can use its identity to:

### Request Access Tokens

```bash
# Get a token as the agent identity
AGENT_TOKEN=$(curl -s -X POST \
  "https://login.microsoftonline.com/${TENANT_ID}/oauth2/v2.0/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=${BLUEPRINT_APP_ID}&client_secret=${BLUEPRINT_SECRET}&scope=https://graph.microsoft.com/.default&grant_type=client_credentials" \
  | jq -r '.access_token')

echo "Agent Token: ${AGENT_TOKEN:0:50}..."
```

### Access Microsoft Graph APIs

```bash
# Example: Get the agent's own profile
curl -s -X GET \
  "https://graph.microsoft.com/v1.0/me" \
  -H "Authorization: Bearer ${AGENT_TOKEN}" | jq '.'
```

## Alternative: Using PowerShell

Microsoft provides a PowerShell module that simplifies this process:

```powershell
# Install the Microsoft Graph PowerShell module
Install-Module -Name Microsoft.Graph.Beta -Scope CurrentUser

# Connect with required scopes
Connect-MgGraph -Scopes "AgentIdentityBlueprint.Create", "AgentIdentityBlueprint.ReadWrite.All", "AgentIdentityBlueprint.AddRemoveCreds.All"

# Follow Microsoft's documentation for PowerShell commands
# See: https://aka.ms/agentidpowershell
```

## 4. Managing Agent Identities

### List All Agent Identities

```bash
curl -s -X GET \
  "https://graph.microsoft.com/beta/serviceprincipals?\$filter=servicePrincipalType eq 'ServiceIdentity'" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | jq '.value[] | {displayName, id, agentIdentityBlueprintId}'
```

### List All Agent Identity Blueprints

```bash
curl -s -X GET \
  "https://graph.microsoft.com/beta/applications?\$filter=@odata.type eq 'microsoft.graph.agentIdentityBlueprint'" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "OData-Version: 4.0" | jq '.value[] | {displayName, appId, id}'
```

## 5. Deleting Created Resources

When you're done testing or want to clean up resources, delete them in the following order to avoid dependency issues:

### Step 1: Delete the Agent Identity

Delete the agent identity first, as it depends on the blueprint:

```bash
# Set the agent identity object ID (from Step 6 verification)
AGENT_IDENTITY_ID="<agent-identity-object-id>"

# Delete the agent identity
curl -s -X DELETE \
  "https://graph.microsoft.com/beta/serviceprincipals/${AGENT_IDENTITY_ID}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "OData-Version: 4.0"

echo "Agent Identity deleted"
```

### Step 2: Delete the Blueprint Principal

Delete the service principal associated with the blueprint:

```bash
# Get the blueprint principal ID
BLUEPRINT_PRINCIPAL_ID=$(curl -s -X GET \
  "https://graph.microsoft.com/beta/serviceprincipals?\$filter=appId eq '${BLUEPRINT_APP_ID}'" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" | jq -r '.value[0].id')

# Delete the blueprint principal
curl -s -X DELETE \
  "https://graph.microsoft.com/beta/serviceprincipals/${BLUEPRINT_PRINCIPAL_ID}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "OData-Version: 4.0"

echo "Blueprint Principal deleted"
```

### Step 3: Delete the Agent Identity Blueprint

> ⚠️ **Warning**: Deleting a blueprint will affect all agent identities created from it. Ensure all dependent agent identities are deleted first.

```bash
# Delete the blueprint application
curl -s -X DELETE \
  "https://graph.microsoft.com/beta/applications/${BLUEPRINT_OBJECT_ID}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

echo "Agent Identity Blueprint deleted"
```

### Step 4: Delete the Automation App Registration

Delete the app registration created in "Setting Up Permissions" (Agent-Identity-Automation):

```bash
# Set the automation app ID (from Step 1 of Setting Up Permissions)
AUTOMATION_APP_ID="<your-automation-app-id>"

# Get the object ID of the app registration
AUTOMATION_OBJECT_ID=$(az ad app show --id $AUTOMATION_APP_ID --query id -o tsv)

# Delete the service principal first
az ad sp delete --id $AUTOMATION_APP_ID

# Delete the app registration
az ad app delete --id $AUTOMATION_APP_ID

echo "Automation App Registration deleted"
```

### Step 5: Remove Role Assignments (GUI)

The role assignments will be automatically cleaned up when the service principal is deleted. However, if you want to verify:

1. Go to [Microsoft Entra admin center](https://entra.microsoft.com)
2. Navigate to: **Roles and administrators** → **Agent ID Administrator**
3. Verify the deleted app no longer appears in the assignments

> **Note**: After deletion, verify in the [Microsoft Entra admin center](https://entra.microsoft.com) that all resources have been removed:
> - **Agent ID (Preview)** → **All agent identities** - should not show deleted identity
> - **App registrations** → **All applications** - should not show deleted apps

## Additional Resources

- [What are Agent Identities](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/what-is-agent-id)
- [Agent Identity Blueprints](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/agent-blueprint)
- [Create Agent Identity Blueprint](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/create-blueprint)
- [Create Agent Identities](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/create-delete-agent-identities)
- [Agent ID PowerShell Module](https://aka.ms/agentidpowershell)
- [Agent ID Administrator Role](https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference#agent-id-administrator)
- [Credentials for Agent Identities](https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/agent-identities#credentials-for-agent-identities)

## API Version Note

> **API Version (as of December 2025)**: The Agent Identity APIs are available only in the Microsoft Graph beta endpoint (`https://graph.microsoft.com/beta/`). These APIs may change before reaching general availability. Monitor the [Microsoft Graph changelog](https://learn.microsoft.com/en-us/graph/changelog) for updates.

## Related Guides

- **Agent Registry**: See [entra-agent-registry.md](./entra-agent-registry.md) for registering agents for visibility/governance
- **Agent Creation**: See [agent-creation.md](./agent-creation.md) for creating agents in Microsoft Foundry

## Documentation Test History
