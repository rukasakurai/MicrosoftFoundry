#!/bin/bash
#
# Stand up a Foundry IQ knowledge base over Azure AI Search and connect a
# Microsoft Foundry agent to it via MCP, then run it far enough to show a
# grounded, cited answer produced by the knowledge_base_retrieve tool.
#
# This is the "managed knowledge base" RAG path (Foundry IQ), distinct from the
# single-shot azure_ai_search tool in scripts/create-rag-agent.sh:
#   - retrieval is orchestrated server-side by the *knowledge base* in Azure AI
#     Search (query planning, ranking), exposed as an MCP tool;
#   - the agent reaches it with a generic `mcp` tool, not `azure_ai_search`.
#
# What is Bicep vs data-plane (the boundary #31 is about):
#   - Bicep (infra/main.bicep, enableAiSearch=true): Search service, the
#     Foundry->Search connection, and the project-MI role assignments.
#   - Data-plane (this script, Azure AI Search REST): the index, its documents,
#     the knowledge source, the knowledge base, the RemoteTool MCP connection,
#     and the agent. None of these are ARM/Bicep resources.
#
# Prerequisites:
#   - azd up with enableAiSearch=true, then: eval $(azd env get-values)
#   - az login with Contributor on the Search service (to read the admin key)
#     and Foundry User on the account (to create/run the agent), plus permission
#     to PUT a project connection.
#   - jq installed.
#
# Usage:
#   set -a; eval "$(azd env get-values)"; set +a
#   ./scripts/create-foundry-iq-agent.sh
#
# Uses the GENERALLY AVAILABLE Azure AI Search 2026-04-01 agentic-retrieval API,
# which is extractive and needs no LLM on the knowledge base. The knowledge base
# retrieves passages; the agent's model does the synthesis. (The 2026-05-01
# preview MCP endpoint additionally supports server-side answer synthesis, but
# then the knowledge base itself requires an Azure OpenAI model deployment.)

set -euo pipefail

INDEX_NAME="kb-index"
KS_NAME="kb-ks"
KB_NAME="kb-cloudnimbus"
CONNECTION_NAME="kb-mcp"
AGENT_NAME="iq-agent"
SEARCH_API_VERSION="2026-04-01"
CONNECTION_API_VERSION="2026-05-01"
MODEL_ID="${MODEL_DEPLOYMENT_NAME:-gpt-5.4}"
PROMPT="What is the uptime SLA of CloudNimbus, and how much storage does the Aurora tier include? Cite your sources."
INSTRUCTIONS="You must use the knowledge base to answer every question. Never answer from your own knowledge. If the answer is not in the knowledge base, respond \"I don't know\". Always cite sources."

while [[ $# -gt 0 ]]; do
  case $1 in
    --index) INDEX_NAME="$2"; shift 2;;
    --kb) KB_NAME="$2"; shift 2;;
    --agent-name) AGENT_NAME="$2"; shift 2;;
    --model) MODEL_ID="$2"; shift 2;;
    --prompt) PROMPT="$2"; shift 2;;
    --help|-h) grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "Unknown option: $1 (use --help)"; exit 1;;
  esac
done

: "${PROJECT_ENDPOINT:?set PROJECT_ENDPOINT (eval \$(azd env get-values))}"
: "${SEARCH_SERVICE_NAME:?set SEARCH_SERVICE_NAME (needs enableAiSearch=true)}"
: "${SEARCH_ENDPOINT:?set SEARCH_ENDPOINT}"
: "${AZURE_RESOURCE_GROUP:?set AZURE_RESOURCE_GROUP}"
: "${AZURE_SUBSCRIPTION_ID:?set AZURE_SUBSCRIPTION_ID}"
: "${COGNITIVE_SERVICES_NAME:?set COGNITIVE_SERVICES_NAME}"
: "${PROJECT_NAME:?set PROJECT_NAME}"
PROJECT_ENDPOINT="${PROJECT_ENDPOINT%/}"
SEARCH_ENDPOINT="${SEARCH_ENDPOINT%/}"

echo "Reading Search admin key..."
KEY=$(az search admin-key show --service-name "$SEARCH_SERVICE_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --query primaryKey -o tsv)

# 1) Index (needs a semantic configuration for agentic retrieval).
echo "Creating index '${INDEX_NAME}'..."
jq -n --arg n "$INDEX_NAME" '{
  name:$n,
  fields:[
    {name:"id",type:"Edm.String",key:true,searchable:false,retrievable:true},
    {name:"title",type:"Edm.String",searchable:true,retrievable:true},
    {name:"url",type:"Edm.String",searchable:false,retrievable:true},
    {name:"content",type:"Edm.String",searchable:true,retrievable:true}
  ],
  semantic:{configurations:[{name:"sem-config",prioritizedFields:{
    titleField:{fieldName:"title"},
    prioritizedContentFields:[{fieldName:"content"}],
    prioritizedKeywordsFields:[]}}]}
}' | curl -fsS -X PUT "$SEARCH_ENDPOINT/indexes/${INDEX_NAME}?api-version=${SEARCH_API_VERSION}" \
  -H "Content-Type: application/json" -H "api-key: $KEY" -d @- >/dev/null
echo "  index ready."

# 2) Sample documents (fictional, so a correct answer can only come from retrieval).
echo "Uploading sample documents..."
jq -n '{value:[
  {"@search.action":"mergeOrUpload",id:"1",title:"CloudNimbus SLA",url:"https://example.com/cloudnimbus/sla",content:"CloudNimbus guarantees a 99.95% uptime SLA for all paid tiers."},
  {"@search.action":"mergeOrUpload",id:"2",title:"CloudNimbus Aurora tier",url:"https://example.com/cloudnimbus/aurora",content:"The CloudNimbus Aurora tier includes 5 TB of included storage and priority support."},
  {"@search.action":"mergeOrUpload",id:"3",title:"CloudNimbus support",url:"https://example.com/cloudnimbus/support",content:"CloudNimbus Aurora tier support responds within 2 business hours."}
]}' | curl -fsS -X POST "$SEARCH_ENDPOINT/indexes/${INDEX_NAME}/docs/index?api-version=${SEARCH_API_VERSION}" \
  -H "Content-Type: application/json" -H "api-key: $KEY" -d @- | jq '{uploaded:[.value[]|{key,status}]}'
sleep 5

# 3) Knowledge source (points at the index) and knowledge base (references it).
echo "Creating knowledge source '${KS_NAME}'..."
jq -n --arg n "$KS_NAME" --arg idx "$INDEX_NAME" '{
  name:$n,kind:"searchIndex",description:"Knowledge source over the sample index.",
  searchIndexParameters:{searchIndexName:$idx,semanticConfigurationName:"sem-config",
    sourceDataFields:[{name:"id"},{name:"title"},{name:"url"},{name:"content"}],
    searchFields:[{name:"title"},{name:"content"}]}
}' | curl -fsS -X PUT "$SEARCH_ENDPOINT/knowledgesources/${KS_NAME}?api-version=${SEARCH_API_VERSION}" \
  -H "Content-Type: application/json" -H "api-key: $KEY" -d @- >/dev/null

echo "Creating knowledge base '${KB_NAME}'..."
jq -n --arg n "$KB_NAME" --arg ks "$KS_NAME" '{
  name:$n,description:"Foundry IQ knowledge base (extractive).",knowledgeSources:[{name:$ks}]
}' | curl -fsS -X PUT "$SEARCH_ENDPOINT/knowledgebases/${KB_NAME}?api-version=${SEARCH_API_VERSION}" \
  -H "Content-Type: application/json" -H "api-key: $KEY" -d @- >/dev/null
echo "  knowledge base ready."

# 4) RemoteTool connection on the (CognitiveServices) project, keyless via the
#    project's managed identity. NOTE: audience must be https://search.azure.com
#    WITHOUT a trailing slash, or the agent's token fetch fails at runtime with
#    "Missing required query parameter 'audience'".
echo "Creating project connection '${CONNECTION_NAME}' (RemoteTool -> KB MCP endpoint)..."
MCP_ENDPOINT="${SEARCH_ENDPOINT}/knowledgebases/${KB_NAME}/mcp?api-version=${SEARCH_API_VERSION}"
CONN_ID="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP}/providers/Microsoft.CognitiveServices/accounts/${COGNITIVE_SERVICES_NAME}/projects/${PROJECT_NAME}/connections/${CONNECTION_NAME}"
ARM_TOKEN=$(az account get-access-token --scope https://management.azure.com/.default --query accessToken -o tsv)
jq -n --arg t "$MCP_ENDPOINT" '{properties:{
  authType:"ProjectManagedIdentity",category:"RemoteTool",target:$t,
  isSharedToAll:true,audience:"https://search.azure.com",metadata:{ApiType:"Azure"}}}' \
  | curl -fsS -X PUT "https://management.azure.com${CONN_ID}?api-version=${CONNECTION_API_VERSION}" \
    -H "Authorization: Bearer ${ARM_TOKEN}" -H "Content-Type: application/json" -d @- \
    | jq '{name,authType:.properties.authType,category:.properties.category,audience:.properties.audience}'

# 5) Agent with the knowledge-base MCP tool. Foundry forbids Authorization
#    headers on mcp tools, so auth must come from project_connection_id.
echo "Creating agent '${AGENT_NAME}' with knowledge_base_retrieve MCP tool..."
TOKEN=$(az account get-access-token --resource https://ai.azure.com --query accessToken -o tsv)
jq -n --arg m "$MODEL_ID" --arg i "$INSTRUCTIONS" --arg u "$MCP_ENDPOINT" --arg c "$CONNECTION_NAME" '{
  description:"Foundry IQ knowledge-base agent (MCP).",
  definition:{kind:"prompt",model:$m,instructions:$i,tools:[{
    type:"mcp",server_label:"knowledge-base",server_url:$u,
    require_approval:"never",allowed_tools:["knowledge_base_retrieve"],
    project_connection_id:$c}]}
}' | curl -fsS -X POST "${PROJECT_ENDPOINT}/agents/${AGENT_NAME}/versions?api-version=v1" \
  -H "Authorization: Bearer ${TOKEN}" -H "Content-Type: application/json" -d @- | jq '{name,version,status}'
sleep 3

# 6) Run and show the grounded answer, citations, and proof the KB was called.
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
