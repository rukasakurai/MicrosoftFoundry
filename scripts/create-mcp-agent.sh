#!/bin/bash
#
# Create a Microsoft Foundry agent that connects to an authenticated remote MCP
# server, and run it far enough to surface the OAuth consent and tool-approval
# steps. This is a minimal, customer-free reference for the connection pattern
# described in docs/agent-mcp-oauth.md.
#
# It demonstrates the DIRECT path: Agent -> remote MCP server, where the MCP
# server's credentials live in a Foundry project connection that the agent
# references by name (project_connection_id).
#
# Prerequisites:
# - Azure CLI authenticated (az login) with access to the Foundry project.
# - A project connection to the MCP server already created (see
#   docs/agent-mcp-oauth.md). For the GitHub MCP server this is an OAuth2
#   connection to https://api.githubcopilot.com/mcp/.
# - A model deployment in the project (default: gpt-4o-mini).
# - jq for JSON parsing.
#
# Usage:
#   eval $(azd env get-values) && ./scripts/create-mcp-agent.sh \
#     --connection github \
#     --prompt "What is my GitHub username? Use the GitHub MCP tools."
#
# The connection must live in the SAME project as PROJECT_ENDPOINT: Foundry
# connections are project-scoped.

set -euo pipefail

# Defaults
MODEL_ID="gpt-4o-mini"
AGENT_NAME="mcp-oauth-agent"
CONNECTION_NAME="github"
SERVER_LABEL="github"
SERVER_URL="https://api.githubcopilot.com/mcp/"
REQUIRE_APPROVAL="always"
PROMPT="What is my GitHub username? Use the GitHub MCP tools."
INSTRUCTIONS="You are a helpful assistant. Use the MCP tools when relevant."

while [[ $# -gt 0 ]]; do
  case $1 in
    --endpoint) ENDPOINT="$2"; shift 2;;
    --model) MODEL_ID="$2"; shift 2;;
    --agent-name) AGENT_NAME="$2"; shift 2;;
    --connection) CONNECTION_NAME="$2"; shift 2;;
    --server-label) SERVER_LABEL="$2"; shift 2;;
    --server-url) SERVER_URL="$2"; shift 2;;
    --require-approval) REQUIRE_APPROVAL="$2"; shift 2;;
    --prompt) PROMPT="$2"; shift 2;;
    --instructions) INSTRUCTIONS="$2"; shift 2;;
    --help|-h)
      grep '^#' "$0" | sed 's/^# \{0,1\}//'
      exit 0;;
    *) echo "Unknown option: $1 (use --help)"; exit 1;;
  esac
done

ENDPOINT="${ENDPOINT:-${PROJECT_ENDPOINT:-}}"
if [ -z "$ENDPOINT" ]; then
  echo "Error: set PROJECT_ENDPOINT (eval \$(azd env get-values)) or pass --endpoint." >&2
  exit 1
fi
ENDPOINT="${ENDPOINT%/}"

echo "Obtaining access token (resource: https://ai.azure.com)..."
TOKEN=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)

# 1) Create (or add a version to) the agent, wiring the MCP tool to the
#    project connection via project_connection_id.
echo "Creating agent '${AGENT_NAME}' with MCP tool -> connection '${CONNECTION_NAME}'..."
CREATE_BODY=$(jq -n \
  --arg model "$MODEL_ID" \
  --arg instructions "$INSTRUCTIONS" \
  --arg label "$SERVER_LABEL" \
  --arg url "$SERVER_URL" \
  --arg approval "$REQUIRE_APPROVAL" \
  --arg connection "$CONNECTION_NAME" \
  '{
    description: "Agent connected to a remote MCP server via a project connection.",
    definition: {
      kind: "prompt",
      model: $model,
      instructions: $instructions,
      tools: [ {
        type: "mcp",
        server_label: $label,
        server_url: $url,
        require_approval: $approval,
        project_connection_id: $connection
      } ]
    }
  }')
curl -fsS -X POST "${ENDPOINT}/agents/${AGENT_NAME}/versions?api-version=v1" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${CREATE_BODY}" | jq '{name, version, status}'

# 2) Run the agent. The Responses API lives at /openai/v1/responses (note: no
#    ?api-version= here; that path is versioned by /v1).
echo "Running agent..."
RUN_BODY=$(jq -n \
  --arg prompt "$PROMPT" \
  --arg name "$AGENT_NAME" \
  '{
    input: $prompt,
    agent_reference: { name: $name, type: "agent_reference" }
  }')
RESP=$(curl -fsS -X POST "${ENDPOINT}/openai/v1/responses" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json" \
  -d "${RUN_BODY}")

echo "$RESP" | jq '{id, status, output: [.output[] | {type, server_label, name, consent_link}]}'

# 2b) Evidence-safe verdict (pass/fail/invalid); || true: non-zero exit is expected.
echo ""
echo "Run verdict (evidence-safe):"
echo "$RESP" | "$(dirname "$0")/verify-agent-run.sh" || true

# 3) Surface the interactive steps the caller must handle.
CONSENT=$(echo "$RESP" | jq -r '.output[]? | select(.type=="oauth_consent_request") | .consent_link' | head -1)
APPROVAL=$(echo "$RESP" | jq -r '.output[]? | select(.type=="mcp_approval_request") | .id' | head -1)

if [ -n "$CONSENT" ] && [ "$CONSENT" != "null" ]; then
  echo ""
  echo "OAuth consent required. Open this link, sign in to the MCP server, and consent:"
  echo "  $CONSENT"
  echo "Then re-run this script (consent is remembered per user, per tool, per project)."
fi

if [ -n "$APPROVAL" ] && [ "$APPROVAL" != "null" ]; then
  echo ""
  echo "Tool-call approval required (approval id: $APPROVAL)."
  echo "Submit an mcp_approval_response with previous_response_id=$(echo "$RESP" | jq -r '.id')."
  echo "See docs/agent-mcp-oauth.md for the approval payload."
fi
