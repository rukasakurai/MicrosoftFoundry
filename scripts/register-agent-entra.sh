#!/bin/bash
#
# Register an AI agent with Microsoft Entra Agent ID registry.
#
# This script registers an agent instance with the Microsoft Entra Agent Registry
# so that it appears in the Agent ID section of the Microsoft Entra admin center
# (https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/AllAgents.MenuView/~/overview).
#
# The registration creates an agent instance in the Agent Registry, making the agent
# discoverable and manageable through Microsoft Entra's centralized identity system.
#
# Prerequisites:
# - Azure CLI installed and authenticated (az login)
# - An Azure AD App Registration with the following Microsoft Graph API permission:
#   - AgentInstance.ReadWrite.All (Application or Delegated permission)
# - The authenticated user or app must have Agent Registry Administrator role
# - jq installed for JSON parsing (optional but recommended)
#
# Usage:
#   # Using environment variables
#   ./register-agent-entra.sh
#
#   # Or specify parameters explicitly
#   ./register-agent-entra.sh --agent-name <name> --display-name <display-name>
#
# For more information on Microsoft Entra Agent ID, see:
# https://learn.microsoft.com/en-us/entra/agent-id/identity-platform/what-is-agent-id
#

set -e

# Default values
AGENT_NAME=""
DISPLAY_NAME=""
AGENT_URL=""
OWNER_ID=""
DESCRIPTION=""
ORIGINATING_STORE="MicrosoftFoundry"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --agent-name)
      AGENT_NAME="$2"
      shift 2
      ;;
    --display-name)
      DISPLAY_NAME="$2"
      shift 2
      ;;
    --agent-url)
      AGENT_URL="$2"
      shift 2
      ;;
    --owner-id)
      OWNER_ID="$2"
      shift 2
      ;;
    --description)
      DESCRIPTION="$2"
      shift 2
      ;;
    --originating-store)
      ORIGINATING_STORE="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Register an AI agent with Microsoft Entra Agent ID registry."
      echo ""
      echo "Options:"
      echo "  --agent-name <name>          Agent name/identifier (required)"
      echo "  --display-name <name>        Human-readable display name (default: same as agent-name)"
      echo "  --agent-url <url>            Agent operational endpoint URL (optional)"
      echo "  --owner-id <id>              Owner object ID (default: current user)"
      echo "  --description <text>         Agent description (optional)"
      echo "  --originating-store <name>   Platform name (default: MicrosoftFoundry)"
      echo "  --help                       Show this help message"
      echo ""
      echo "Examples:"
      echo "  # Register an agent with minimal parameters"
      echo "  $0 --agent-name my-agent"
      echo ""
      echo "  # Full customization"
      echo "  $0 \\"
      echo "    --agent-name foundry-agent \\"
      echo "    --display-name \"My Foundry Agent\" \\"
      echo "    --agent-url https://myagent.example.com/execute \\"
      echo "    --description \"Customer service automation agent\""
      echo ""
      echo "Prerequisites:"
      echo "  - Azure CLI authenticated (az login)"
      echo "  - Microsoft Graph API permission: AgentInstance.ReadWrite.All"
      echo "  - Agent Registry Administrator role in Microsoft Entra"
      echo ""
      echo "For more information, see docs/entra-agent-registry.md"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [ -z "$AGENT_NAME" ]; then
  echo "Error: --agent-name is required."
  echo "Use --help for usage information."
  exit 1
fi

# Set defaults
if [ -z "$DISPLAY_NAME" ]; then
  DISPLAY_NAME="$AGENT_NAME"
fi

# Get owner ID from current user if not provided
if [ -z "$OWNER_ID" ]; then
  echo "Obtaining current user's object ID..."
  OWNER_ID=$(az ad signed-in-user show --query id -o tsv 2>/dev/null || true)
  
  if [ -z "$OWNER_ID" ]; then
    echo "Warning: Could not obtain current user's object ID."
    echo "You can provide --owner-id explicitly, or ensure you're logged in with 'az login'."
    echo "Proceeding without owner ID..."
  fi
fi

echo "Registering agent with Microsoft Entra Agent ID..."
echo "  Agent Name: ${AGENT_NAME}"
echo "  Display Name: ${DISPLAY_NAME}"
if [ -n "$AGENT_URL" ]; then
  echo "  Agent URL: ${AGENT_URL}"
fi
if [ -n "$OWNER_ID" ]; then
  echo "  Owner ID: ${OWNER_ID}"
fi
echo "  Originating Store: ${ORIGINATING_STORE}"
echo ""

# Get Microsoft Graph access token
echo "Obtaining Microsoft Graph access token..."
ACCESS_TOKEN=$(az account get-access-token --resource https://graph.microsoft.com --query accessToken -o tsv)

if [ -z "$ACCESS_TOKEN" ]; then
  echo "Error: Failed to obtain access token for Microsoft Graph."
  echo "Please run 'az login' first."
  exit 1
fi

# Build request body
# Start with required fields
REQUEST_BODY='{'
REQUEST_BODY+='"displayName": "'"${DISPLAY_NAME}"'"'

# Add ownerIds if available
if [ -n "$OWNER_ID" ]; then
  REQUEST_BODY+=', "ownerIds": ["'"${OWNER_ID}"'"]'
fi

# Add optional fields
if [ -n "$AGENT_URL" ]; then
  REQUEST_BODY+=', "url": "'"${AGENT_URL}"'"'
fi

REQUEST_BODY+=', "originatingStore": "'"${ORIGINATING_STORE}"'"'

# Note: Description is not directly supported by the agentInstance API.
# To add metadata like description, use an agent card/manifest after registration.

REQUEST_BODY+='}'

echo "Sending request to Microsoft Graph API..."

# Make API request to register agent instance
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "https://graph.microsoft.com/beta/agentRegistry/agentInstances" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${REQUEST_BODY}")

# Extract HTTP status code (last line)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

# Extract response body (all but last line)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

# Check if request was successful
if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  echo "✓ Agent registered successfully with Microsoft Entra Agent ID!"
  echo ""
  
  # Try to parse and display response with jq if available
  if command -v jq >/dev/null 2>&1; then
    echo "Agent Instance Details:"
    echo "$RESPONSE_BODY" | jq '.'
    
    INSTANCE_ID=$(echo "$RESPONSE_BODY" | jq -r '.id // empty')
    if [ -n "$INSTANCE_ID" ]; then
      echo ""
      echo "Agent Instance ID: ${INSTANCE_ID}"
    fi
  else
    echo "Response:"
    echo "$RESPONSE_BODY"
    echo ""
    echo "Tip: Install 'jq' for better JSON formatting"
  fi
  
  echo ""
  echo "================================================================"
  echo "Agent registration completed successfully!"
  echo "================================================================"
  echo ""
  echo "Your agent should now be visible in the Microsoft Entra admin center:"
  echo "  https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/AllAgents.MenuView/~/overview"
  echo ""
  echo "Next steps:"
  echo "  1. Verify the agent appears in the Entra Agent ID section"
  echo "  2. Configure additional governance policies as needed"
  echo "  3. Assign appropriate permissions and access controls"
  echo ""
  echo "For more information, see docs/entra-agent-registry.md"
else
  echo "✗ Error: Failed to register agent (HTTP ${HTTP_CODE})"
  echo ""
  
  # Check for specific error conditions and provide guidance
  if [ "$HTTP_CODE" -eq 401 ] || [ "$HTTP_CODE" -eq 403 ]; then
    echo "Authentication/Authorization Error"
    echo ""
    echo "This error typically occurs when:"
    echo "  1. The signed-in user doesn't have 'Agent Registry Administrator' role"
    echo "  2. The app/user doesn't have 'AgentInstance.ReadWrite.All' permission"
    echo "  3. Admin consent hasn't been granted for the required permissions"
    echo ""
    echo "To resolve:"
    echo "  1. Ensure you have the Agent Registry Administrator role in Microsoft Entra"
    echo "  2. If using an app registration, grant AgentInstance.ReadWrite.All permission"
    echo "  3. Have an admin grant consent for the permissions"
    echo ""
    echo "See docs/entra-agent-registry.md for detailed setup instructions."
  fi
  
  echo "Response:"
  if command -v jq >/dev/null 2>&1; then
    echo "$RESPONSE_BODY" | jq '.' 2>/dev/null || echo "$RESPONSE_BODY"
  else
    echo "$RESPONSE_BODY"
  fi
  exit 1
fi
