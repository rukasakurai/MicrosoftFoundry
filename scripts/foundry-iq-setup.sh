#!/bin/bash
#
# azd postprovision hook: build the Foundry IQ knowledge base substrate on the
# Azure AI Search service that Bicep provisioned (infra/main.bicep,
# enableFoundryIq=true). Creates, idempotently:
#   index (with a semantic configuration) -> sample documents ->
#   knowledge source -> knowledge base
#
# These are Azure AI Search *data-plane* objects (not ARM/Bicep). The Bicep half
# owns the Search service, the project's Search Index Data Reader role, the
# deploying principal's Search Service Contributor + Search Index Data
# Contributor roles (which this hook uses), and the RemoteTool connection to
# this knowledge base's MCP endpoint.
#
# Auth is keyless: the hook calls the Search data-plane with the deploying
# principal's Entra token (no admin key). Because Bicep grants those roles in the
# same `azd up` and Entra RBAC is eventually consistent, the first write is
# retried until the assignment propagates.
#
# No-op unless ENABLE_FOUNDRY_IQ is "true", so it is safe to leave wired as a
# postprovision hook for the default (Foundry IQ off) deployment.
#
# Environment (azd provides these as outputs after provisioning):
#   ENABLE_FOUNDRY_IQ, SEARCH_ENDPOINT, KNOWLEDGE_BASE_NAME, SEARCH_API_VERSION

set -euo pipefail

if [ "${ENABLE_FOUNDRY_IQ:-false}" != "true" ]; then
  echo "Foundry IQ disabled (ENABLE_FOUNDRY_IQ != true); skipping knowledge base setup."
  exit 0
fi

: "${SEARCH_ENDPOINT:?}"
KB_NAME="${KNOWLEDGE_BASE_NAME:-kb-foundry-iq}"
API_VERSION="${SEARCH_API_VERSION:-2026-04-01}"
INDEX_NAME="${FOUNDRY_IQ_INDEX_NAME:-kb-index}"
KS_NAME="${FOUNDRY_IQ_KS_NAME:-kb-ks}"
SEARCH_ENDPOINT="${SEARCH_ENDPOINT%/}"

echo "Acquiring Entra token for Azure AI Search (keyless)..."
TOKEN=$(az account get-access-token --scope https://search.azure.com/.default --query accessToken -o tsv)

echo "Creating index '${INDEX_NAME}' (with semantic configuration)..."
INDEX_BODY=$(jq -n --arg n "$INDEX_NAME" '{
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
}')
# The role assignments this hook relies on are created by Bicep during the same
# `azd up`; Entra RBAC is eventually consistent, so the first write can 403 until
# it propagates. Retry the first call to absorb that lag.
attempt=0
until printf '%s' "$INDEX_BODY" | curl -fsS -X PUT "$SEARCH_ENDPOINT/indexes/${INDEX_NAME}?api-version=${API_VERSION}" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d @- >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 10 ]; then
    echo "  index create still failing after $attempt attempts; retrying once more with error output:" >&2
    printf '%s' "$INDEX_BODY" | curl -fsS -X PUT "$SEARCH_ENDPOINT/indexes/${INDEX_NAME}?api-version=${API_VERSION}" \
      -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d @- >/dev/null
    break
  fi
  echo "  waiting for Search RBAC to propagate (attempt ${attempt}/10)..."
  sleep 15
done

echo "Uploading sample documents..."
jq -n '{value:[
  {"@search.action":"mergeOrUpload",id:"1",title:"Contoso Cloud SLA",url:"https://example.com/contoso/sla",content:"Contoso Cloud guarantees a 99.95% uptime SLA for all paid tiers."},
  {"@search.action":"mergeOrUpload",id:"2",title:"Contoso Cloud Enterprise tier",url:"https://example.com/contoso/enterprise",content:"The Contoso Cloud Enterprise tier includes 5 TB of included storage and priority support."},
  {"@search.action":"mergeOrUpload",id:"3",title:"Contoso Cloud support",url:"https://example.com/contoso/support",content:"Contoso Cloud Enterprise tier support responds within 2 business hours."}
]}' | curl -fsS -X POST "$SEARCH_ENDPOINT/indexes/${INDEX_NAME}/docs/index?api-version=${API_VERSION}" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d @- | jq '{uploaded:[.value[]|{key,status}]}'

echo "Creating knowledge source '${KS_NAME}'..."
jq -n --arg n "$KS_NAME" --arg idx "$INDEX_NAME" '{
  name:$n,kind:"searchIndex",description:"Knowledge source over the sample index.",
  searchIndexParameters:{searchIndexName:$idx,semanticConfigurationName:"sem-config",
    sourceDataFields:[{name:"id"},{name:"title"},{name:"url"},{name:"content"}],
    searchFields:[{name:"title"},{name:"content"}]}
}' | curl -fsS -X PUT "$SEARCH_ENDPOINT/knowledgesources/${KS_NAME}?api-version=${API_VERSION}" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d @- >/dev/null

echo "Creating knowledge base '${KB_NAME}'..."
jq -n --arg n "$KB_NAME" --arg ks "$KS_NAME" '{
  name:$n,description:"Foundry IQ knowledge base (extractive).",knowledgeSources:[{name:$ks}]
}' | curl -fsS -X PUT "$SEARCH_ENDPOINT/knowledgebases/${KB_NAME}?api-version=${API_VERSION}" \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" -d @- >/dev/null

echo "Foundry IQ knowledge base '${KB_NAME}' is ready."
echo "Create and run an agent against it with: scripts/create-foundry-iq-agent.sh"
