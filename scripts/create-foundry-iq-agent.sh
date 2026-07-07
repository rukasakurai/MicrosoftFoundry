#!/bin/bash
#
# Create a Microsoft Foundry agent that answers from a Foundry IQ knowledge base
# via MCP, then run it far enough to show a grounded, cited answer produced by
# the knowledge_base_retrieve tool.
#
# This assumes the Foundry IQ substrate already exists:
#   - Bicep (infra/main.bicep, enableFoundryIq=true) provisioned the Search
#     service, the project's Search Index Data Reader role, and the RemoteTool
#     connection (KNOWLEDGE_BASE_CONNECTION_NAME) to the knowledge base MCP
#     endpoint.
#   - scripts/foundry-iq-setup.sh (azd postprovision hook) created the index,
#     documents, knowledge source, and knowledge base (KNOWLEDGE_BASE_NAME).
#
# This script only creates the agent and runs it; it does not create the
# connection or the knowledge base.
#
# Prerequisites:
#   - azd up with enableFoundryIq=true, then: eval $(azd env get-values)
#   - az login with Foundry User on the account.
#   - jq installed.
#
# Usage:
#   set -a; eval "$(azd env get-values)"; set +a
#   ./scripts/create-foundry-iq-agent.sh

set -euo pipefail

AGENT_NAME="iq-agent"
MODEL_ID="${MODEL_DEPLOYMENT_NAME:-gpt-5.4}"
PROMPT="What is the uptime SLA of Contoso Cloud, and how much storage does the Enterprise tier include? Cite your sources."
INSTRUCTIONS="You must use the knowledge base to answer every question. Never answer from your own knowledge. If the answer is not in the knowledge base, respond \"I don't know\". Always cite sources."
CREATE_ONLY=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --agent-name) AGENT_NAME="$2"; shift 2;;
    --model) MODEL_ID="$2"; shift 2;;
    --prompt) PROMPT="$2"; shift 2;;
    --create-only) CREATE_ONLY=true; shift;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "Unknown option: $1 (use --help)"; exit 1;;
  esac
done

: "${PROJECT_ENDPOINT:?set PROJECT_ENDPOINT (eval \$(azd env get-values))}"
: "${SEARCH_ENDPOINT:?set SEARCH_ENDPOINT (needs enableFoundryIq=true)}"
: "${KNOWLEDGE_BASE_NAME:?set KNOWLEDGE_BASE_NAME}"
: "${KNOWLEDGE_BASE_CONNECTION_NAME:?set KNOWLEDGE_BASE_CONNECTION_NAME}"
PROJECT_ENDPOINT="${PROJECT_ENDPOINT%/}"
SEARCH_ENDPOINT="${SEARCH_ENDPOINT%/}"
API_VERSION="${SEARCH_API_VERSION:-2026-04-01}"
MCP_ENDPOINT="${SEARCH_ENDPOINT}/knowledgebases/${KNOWLEDGE_BASE_NAME}/mcp?api-version=${API_VERSION}"

TOKEN=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)

# Create (or version) the agent. Foundry forbids Authorization headers on mcp
# tools, so auth comes from project_connection_id (the Bicep RemoteTool
# connection, which uses the project's managed identity).
echo "Creating agent '${AGENT_NAME}' with knowledge_base_retrieve MCP tool..."
jq -n --arg m "$MODEL_ID" --arg i "$INSTRUCTIONS" --arg u "$MCP_ENDPOINT" --arg c "$KNOWLEDGE_BASE_CONNECTION_NAME" '{
  description:"Foundry IQ knowledge-base agent (MCP).",
  definition:{kind:"prompt",model:$m,instructions:$i,tools:[{
    type:"mcp",server_label:"knowledge-base",server_url:$u,
    require_approval:"never",allowed_tools:["knowledge_base_retrieve"],
    project_connection_id:$c}]}
}' | curl -fsS -X POST "${PROJECT_ENDPOINT}/agents/${AGENT_NAME}/versions?api-version=v1" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" -d @- | jq '{name,version,status}'

if [ "$CREATE_ONLY" = true ]; then
  echo "Agent '${AGENT_NAME}' created. Ask it a question by re-running this script without --create-only."
  exit 0
fi
sleep 3

echo "Running agent..."
RESP=$(jq -n --arg p "$PROMPT" --arg n "$AGENT_NAME" '{
  input:$p,agent_reference:{name:$n,type:"agent_reference"}
}' | curl -fsS -X POST "${PROJECT_ENDPOINT}/openai/v1/responses" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" -d @-)

echo ""
echo "Answer:"
echo "$RESP" | jq -r '.output_text // (.output[]?|select(.type=="message")|.content[]?.text // empty)'
echo ""
echo "Proof the knowledge base was invoked (output item types):"
echo "$RESP" | jq -c '[.output[]?.type]'
echo "$RESP" | jq -r '[.output[]?|select(.type=="mcp_call")|.name] as $c | "  knowledge_base_retrieve calls: \($c|length)"'
