#!/bin/bash
#
# Create an AI agent in Microsoft Foundry using REST API and Azure CLI.
#
# This script demonstrates how to programmatically create an agent in a Microsoft Foundry
# project that has been provisioned with Bicep templates.
#
# Prerequisites:
# - Azure CLI installed and authenticated (az login)
# - jq installed for JSON parsing (optional but recommended)
#
# Usage:
#   # Using environment variables from azd
#   ./create-agent.sh
#
#   # Or specify parameters explicitly
#   ./create-agent.sh --endpoint <endpoint> --project <project-name> --model <model-id>
#
# Environment Variables (from 'azd env get-values'):
#   COGNITIVE_SERVICES_ENDPOINT: Azure AI Services endpoint URL
#   PROJECT_NAME: Name of the Foundry project
#

set -e

# Default values
MODEL_ID="${MODEL_DEPLOYMENT_NAME:-gpt-5.4}"
AGENT_NAME="foundry-agent"
AGENT_INSTRUCTIONS="You are a helpful AI assistant."
AGENT_DESCRIPTION="Agent created programmatically via REST API"
API_VERSION="2025-05-15-preview"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --endpoint)
      ENDPOINT="$2"
      shift 2
      ;;
    --project)
      PROJECT_NAME="$2"
      shift 2
      ;;
    --model)
      MODEL_ID="$2"
      shift 2
      ;;
    --name)
      AGENT_NAME="$2"
      shift 2
      ;;
    --instructions)
      AGENT_INSTRUCTIONS="$2"
      shift 2
      ;;
    --description)
      AGENT_DESCRIPTION="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Create an AI agent in Microsoft Foundry using REST API."
      echo ""
      echo "Options:"
      echo "  --endpoint <url>        Azure AI Services endpoint (default: from COGNITIVE_SERVICES_ENDPOINT env var)"
      echo "  --project <name>        Project name (default: from PROJECT_NAME env var)"
      echo "  --model <id>            Model deployment ID (default: gpt-5.4)"
      echo "  --name <name>           Agent name (default: foundry-agent)"
      echo "  --instructions <text>   Agent instructions (default: 'You are a helpful AI assistant.')"
      echo "  --description <text>    Agent description (default: 'Agent created programmatically via REST API')"
      echo "  --help                  Show this help message"
      echo ""
      echo "Examples:"
      echo "  # Use environment variables from azd"
      echo "  $0"
      echo ""
      echo "  # Specify custom parameters"
      echo "  $0 --model gpt-4-turbo --name my-assistant"
      echo ""
      echo "  # Full customization"
      echo "  $0 \\"
      echo "    --endpoint https://cog-abc123.services.ai.azure.com \\"
      echo "    --project my-project \\"
      echo "    --model gpt-5.4 \\"
      echo "    --name custom-agent \\"
      echo "    --instructions 'You are a specialized customer service agent' \\"
      echo "    --description 'Customer service automation agent'"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Get endpoint from environment if not provided
# Try PROJECT_ENDPOINT first (new pattern), fall back to COGNITIVE_SERVICES_ENDPOINT (legacy)
if [ -z "$ENDPOINT" ]; then
  ENDPOINT="${PROJECT_ENDPOINT:-${COGNITIVE_SERVICES_ENDPOINT}}"
  if [ -z "$ENDPOINT" ]; then
    echo "Error: PROJECT_ENDPOINT or COGNITIVE_SERVICES_ENDPOINT environment variable not found."
    echo "Run 'eval \$(azd env get-values)' or provide --endpoint parameter."
    exit 1
  fi
fi

# Check project name is available (only needed if endpoint doesn't include project path)
if [[ "$ENDPOINT" != */api/projects/* ]] && [ -z "$PROJECT_NAME" ]; then
  echo "Error: PROJECT_NAME environment variable not found."
  echo "Run 'eval \$(azd env get-values)' or provide --project parameter."
  exit 1
fi

# Remove trailing slash from endpoint if present
ENDPOINT="${ENDPOINT%/}"

# Construct API URL for agent versions (new agents API)
if [[ "$ENDPOINT" == */api/projects/* ]]; then
  API_URL="${ENDPOINT}/agents/${AGENT_NAME}/versions?api-version=${API_VERSION}"
else
  API_URL="${ENDPOINT}/api/projects/${PROJECT_NAME}/agents/${AGENT_NAME}/versions?api-version=${API_VERSION}"
fi

echo "Creating agent '${AGENT_NAME}' in project..."
echo "  Endpoint: ${ENDPOINT}"
echo "  Project: ${PROJECT_NAME}"
echo "  Model: ${MODEL_ID}"
echo ""

# Get Azure AD access token (use https://ai.azure.com for Foundry Agent Service)
echo "Obtaining Azure AD access token..."
ACCESS_TOKEN=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)

if [ -z "$ACCESS_TOKEN" ]; then
  echo "Error: Failed to obtain access token. Please run 'az login' first."
  exit 1
fi

# Create request body (new agents API format)
REQUEST_BODY=$(cat <<EOF
{
  "description": "${AGENT_DESCRIPTION}",
  "definition": {
    "kind": "prompt",
    "model": "${MODEL_ID}",
    "instructions": "${AGENT_INSTRUCTIONS}"
  }
}
EOF
)

echo "Sending request to create agent..."

# Make API request
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${API_URL}" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${REQUEST_BODY}")

# Extract HTTP status code (last line)
HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

# Extract response body (all but last line)
RESPONSE_BODY=$(echo "$RESPONSE" | sed '$d')

# Check if request was successful
if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
  echo "✓ Agent created successfully!"
  echo ""
  
  # Try to parse and display response with jq if available
  if command -v jq &> /dev/null; then
    echo "Agent Details:"
    echo "$RESPONSE_BODY" | jq '.'
    
    AGENT_NAME_RESP=$(echo "$RESPONSE_BODY" | jq -r '.name // empty')
    AGENT_VERSION=$(echo "$RESPONSE_BODY" | jq -r '.version // empty')
    if [ -n "$AGENT_NAME_RESP" ] && [ -n "$AGENT_VERSION" ]; then
      echo ""
      echo "Agent: ${AGENT_NAME_RESP}:${AGENT_VERSION}"
    fi
  else
    echo "Response:"
    echo "$RESPONSE_BODY"
    echo ""
    echo "Tip: Install 'jq' for better JSON formatting"
  fi
  
  echo ""
  echo "================================================================"
  echo "Agent creation completed successfully!"
  echo "================================================================"
  echo ""
  echo "Next steps:"
  echo "  1. View your agent in Microsoft Foundry portal"
  echo "  2. Test the agent with a conversation thread"
  echo "  3. Publish the agent to an application for external access"
  echo ""
  echo "For more information, see docs/agent-creation.md"
else
  echo "✗ Error: Failed to create agent (HTTP ${HTTP_CODE})"
  echo ""
  echo "Response:"
  echo "$RESPONSE_BODY"
  exit 1
fi
