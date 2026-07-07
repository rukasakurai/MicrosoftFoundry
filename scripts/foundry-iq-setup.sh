#!/bin/bash
#
# azd postprovision hook: build the Foundry IQ knowledge base substrate on the
# Azure AI Search service that Bicep provisioned (infra/main.bicep,
# enableFoundryIq=true). Creates, idempotently:
#   index (with a semantic configuration) -> sample documents ->
#   knowledge source -> knowledge base
#
# These are Azure AI Search *data-plane* objects (not ARM/Bicep). The Bicep half
# owns the Search service, the project's Search Index Data Reader role, and the
# RemoteTool connection to this knowledge base's MCP endpoint.
#
# No-op unless ENABLE_FOUNDRY_IQ is "true", so it is safe to leave wired as a
# postprovision hook for the default (Foundry IQ off) deployment.
#
# Environment (azd provides these as outputs after provisioning):
#   ENABLE_FOUNDRY_IQ, SEARCH_SERVICE_NAME, SEARCH_ENDPOINT, KNOWLEDGE_BASE_NAME,
#   SEARCH_API_VERSION, AZURE_RESOURCE_GROUP

set -euo pipefail

if [ "${ENABLE_FOUNDRY_IQ:-false}" != "true" ]; then
  echo "Foundry IQ disabled (ENABLE_FOUNDRY_IQ != true); skipping knowledge base setup."
  exit 0
fi

: "${SEARCH_SERVICE_NAME:?}"; : "${SEARCH_ENDPOINT:?}"; : "${AZURE_RESOURCE_GROUP:?}"
KB_NAME="${KNOWLEDGE_BASE_NAME:-kb-foundry-iq}"
API_VERSION="${SEARCH_API_VERSION:-2026-04-01}"
INDEX_NAME="${FOUNDRY_IQ_INDEX_NAME:-kb-index}"
KS_NAME="${FOUNDRY_IQ_KS_NAME:-kb-ks}"
SEARCH_ENDPOINT="${SEARCH_ENDPOINT%/}"

echo "Reading Search admin key..."
KEY=$(az search admin-key show --service-name "$SEARCH_SERVICE_NAME" --resource-group "$AZURE_RESOURCE_GROUP" --query primaryKey -o tsv)

echo "Creating index '${INDEX_NAME}' (with semantic configuration)..."
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
}' | curl -fsS -X PUT "$SEARCH_ENDPOINT/indexes/${INDEX_NAME}?api-version=${API_VERSION}" \
  -H "Content-Type: application/json" -H "api-key: $KEY" -d @- >/dev/null

echo "Uploading sample documents..."
jq -n '{value:[
  {"@search.action":"mergeOrUpload",id:"1",title:"CloudNimbus SLA",url:"https://example.com/cloudnimbus/sla",content:"CloudNimbus guarantees a 99.95% uptime SLA for all paid tiers."},
  {"@search.action":"mergeOrUpload",id:"2",title:"CloudNimbus Aurora tier",url:"https://example.com/cloudnimbus/aurora",content:"The CloudNimbus Aurora tier includes 5 TB of included storage and priority support."},
  {"@search.action":"mergeOrUpload",id:"3",title:"CloudNimbus support",url:"https://example.com/cloudnimbus/support",content:"CloudNimbus Aurora tier support responds within 2 business hours."}
]}' | curl -fsS -X POST "$SEARCH_ENDPOINT/indexes/${INDEX_NAME}/docs/index?api-version=${API_VERSION}" \
  -H "Content-Type: application/json" -H "api-key: $KEY" -d @- | jq '{uploaded:[.value[]|{key,status}]}'

echo "Creating knowledge source '${KS_NAME}'..."
jq -n --arg n "$KS_NAME" --arg idx "$INDEX_NAME" '{
  name:$n,kind:"searchIndex",description:"Knowledge source over the sample index.",
  searchIndexParameters:{searchIndexName:$idx,semanticConfigurationName:"sem-config",
    sourceDataFields:[{name:"id"},{name:"title"},{name:"url"},{name:"content"}],
    searchFields:[{name:"title"},{name:"content"}]}
}' | curl -fsS -X PUT "$SEARCH_ENDPOINT/knowledgesources/${KS_NAME}?api-version=${API_VERSION}" \
  -H "Content-Type: application/json" -H "api-key: $KEY" -d @- >/dev/null

echo "Creating knowledge base '${KB_NAME}'..."
jq -n --arg n "$KB_NAME" --arg ks "$KS_NAME" '{
  name:$n,description:"Foundry IQ knowledge base (extractive).",knowledgeSources:[{name:$ks}]
}' | curl -fsS -X PUT "$SEARCH_ENDPOINT/knowledgebases/${KB_NAME}?api-version=${API_VERSION}" \
  -H "Content-Type: application/json" -H "api-key: $KEY" -d @- >/dev/null

echo "Foundry IQ knowledge base '${KB_NAME}' is ready."
echo "Create and run an agent against it with: scripts/create-foundry-iq-agent.sh"
