#!/bin/bash
#
# Create a Microsoft Foundry agent that does retrieval-augmented generation (RAG)
# over an Azure AI Search index, and run it far enough to show a grounded, cited
# answer. This is the data-plane half of the RAG spike; the Bicep half (Search
# service, keyless Foundry->Search connection, and role assignments) is
# provisioned by infra/main.bicep when enableAiSearch=true.
#
# It demonstrates the boundary called out in issue #31: the search index, its
# documents, and the agent + azure_ai_search tool are Azure AI Search / Foundry
# *data-plane* objects created here (REST), not ARM/Bicep resources.
#
# Prerequisites:
# - azd up run with enableAiSearch=true, then: eval $(azd env get-values)
# - Azure CLI authenticated (az login) with Contributor on the Search service
#   (used to read the admin key for index management) and the Foundry User role
#   on the account (used to create and run the agent).
# - jq installed.
#
# Usage:
#   eval $(azd env get-values) && ./scripts/create-rag-agent.sh
#
# Environment variables (from azd outputs):
#   PROJECT_ENDPOINT        Foundry project endpoint
#   MODEL_DEPLOYMENT_NAME   Model deployment id the agent binds to
#   SEARCH_SERVICE_NAME     Azure AI Search service name
#   SEARCH_ENDPOINT         https://<search>.search.windows.net
#   SEARCH_CONNECTION_ID    Full resource id of the Foundry->Search connection
#   AZURE_RESOURCE_GROUP    Resource group holding the Search service

set -euo pipefail

MODEL_ID="${MODEL_DEPLOYMENT_NAME:-gpt-5.4}"
AGENT_NAME="rag-agent"
INDEX_NAME="kb-index"
SEARCH_API_VERSION="2024-07-01"
PROMPT="What is the uptime SLA of CloudNimbus, and how much storage does the Aurora tier include? Cite your sources."
INSTRUCTIONS="You are a helpful assistant. Answer only from the Azure AI Search tool results. Always cite sources."

while [[ $# -gt 0 ]]; do
  case $1 in
    --endpoint) PROJECT_ENDPOINT="$2"; shift 2;;
    --model) MODEL_ID="$2"; shift 2;;
    --agent-name) AGENT_NAME="$2"; shift 2;;
    --index) INDEX_NAME="$2"; shift 2;;
    --search-service) SEARCH_SERVICE_NAME="$2"; shift 2;;
    --resource-group) AZURE_RESOURCE_GROUP="$2"; shift 2;;
    --connection-id) SEARCH_CONNECTION_ID="$2"; shift 2;;
    --prompt) PROMPT="$2"; shift 2;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "Unknown option: $1 (use --help)"; exit 1;;
  esac
done

: "${PROJECT_ENDPOINT:?set PROJECT_ENDPOINT (eval \$(azd env get-values))}"
: "${SEARCH_SERVICE_NAME:?set SEARCH_SERVICE_NAME (needs enableAiSearch=true)}"
: "${SEARCH_ENDPOINT:?set SEARCH_ENDPOINT}"
: "${SEARCH_CONNECTION_ID:?set SEARCH_CONNECTION_ID}"
: "${AZURE_RESOURCE_GROUP:?set AZURE_RESOURCE_GROUP}"
PROJECT_ENDPOINT="${PROJECT_ENDPOINT%/}"
SEARCH_ENDPOINT="${SEARCH_ENDPOINT%/}"

echo "Reading Search admin key for index management..."
ADMIN_KEY=$(az search admin-key show \
  --service-name "$SEARCH_SERVICE_NAME" \
  --resource-group "$AZURE_RESOURCE_GROUP" \
  --query primaryKey -o tsv)

# 1) Create the index (idempotent: PUT replaces if it exists). A plain text
#    index is enough for query_type "simple" (keyword search, no embeddings).
echo "Creating index '${INDEX_NAME}'..."
INDEX_DEF=$(jq -n --arg name "$INDEX_NAME" '{
  name: $name,
  fields: [
    { name: "id",      type: "Edm.String", key: true,  searchable: false, retrievable: true },
    { name: "title",   type: "Edm.String", searchable: true,  retrievable: true },
    { name: "url",     type: "Edm.String", searchable: false, retrievable: true },
    { name: "content", type: "Edm.String", searchable: true,  retrievable: true }
  ]
}')
curl -fsS -X PUT "${SEARCH_ENDPOINT}/indexes/${INDEX_NAME}?api-version=${SEARCH_API_VERSION}" \
  -H "Content-Type: application/json" -H "api-key: ${ADMIN_KEY}" \
  -d "$INDEX_DEF" >/dev/null
echo "  index ready."

# 2) Upload a small, self-contained knowledge base. The facts are fictional so a
#    correct answer can only come from retrieval, not model priors.
echo "Uploading sample documents..."
DOCS=$(jq -n '{
  value: [
    { "@search.action": "mergeOrUpload", id: "1", title: "CloudNimbus SLA",
      url: "https://example.com/cloudnimbus/sla",
      content: "CloudNimbus guarantees a 99.95% uptime SLA for all paid tiers." },
    { "@search.action": "mergeOrUpload", id: "2", title: "CloudNimbus Aurora tier",
      url: "https://example.com/cloudnimbus/aurora",
      content: "The CloudNimbus Aurora tier includes 5 TB of included storage and priority support." },
    { "@search.action": "mergeOrUpload", id: "3", title: "CloudNimbus support",
      url: "https://example.com/cloudnimbus/support",
      content: "CloudNimbus Aurora tier support responds within 2 business hours." }
  ]
}')
curl -fsS -X POST "${SEARCH_ENDPOINT}/indexes/${INDEX_NAME}/docs/index?api-version=${SEARCH_API_VERSION}" \
  -H "Content-Type: application/json" -H "api-key: ${ADMIN_KEY}" \
  -d "$DOCS" | jq '{uploaded: [.value[] | {key, status}]}'
echo "Waiting for indexing to settle..."
sleep 5

# 3) Create (or version) the agent, binding the azure_ai_search tool to the
#    keyless Foundry->Search connection provisioned by Bicep.
TOKEN=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)
echo "Creating agent '${AGENT_NAME}' with azure_ai_search tool..."
CREATE_BODY=$(jq -n \
  --arg model "$MODEL_ID" --arg instructions "$INSTRUCTIONS" \
  --arg conn "$SEARCH_CONNECTION_ID" --arg index "$INDEX_NAME" '{
  description: "RAG agent grounded in an Azure AI Search index.",
  definition: {
    kind: "prompt",
    model: $model,
    instructions: $instructions,
    tools: [ {
      type: "azure_ai_search",
      azure_ai_search: { indexes: [ {
        project_connection_id: $conn,
        index_name: $index,
        query_type: "simple",
        top_k: 5
      } ] }
    } ]
  }
}')
curl -fsS -X POST "${PROJECT_ENDPOINT}/agents/${AGENT_NAME}/versions?api-version=v1" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d "$CREATE_BODY" | jq '{name, version, status}'

# 4) Run the agent and show the grounded answer + citations.
echo "Running agent..."
RUN_BODY=$(jq -n --arg prompt "$PROMPT" --arg name "$AGENT_NAME" '{
  input: $prompt,
  tool_choice: "required",
  agent_reference: { name: $name, type: "agent_reference" }
}')
RESP=$(curl -fsS -X POST "${PROJECT_ENDPOINT}/openai/v1/responses" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" \
  -d "$RUN_BODY")

echo ""
echo "Answer:"
echo "$RESP" | jq -r '.output_text // (.output[]? | select(.type=="message") | .content[]? | .text // empty)'
echo ""
echo "Citations:"
echo "$RESP" | jq -r '[.output[]? | select(.type=="message") | .content[]?.annotations[]? | select(.type=="url_citation") | {title, url}] | if length==0 then "  (none found)" else (.[] | "  - \(.title // "source"): \(.url)") end'
echo ""
echo "Tool calls (proof retrieval ran):"
echo "$RESP" | jq -r '[.output[]? | select(.type|test("search"))] | length as $n | "  \($n) azure_ai_search call(s)"'
