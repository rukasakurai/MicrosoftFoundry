targetScope = 'resourceGroup'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Object ID of the deploying user or service principal. Provided automatically by azd as AZURE_PRINCIPAL_ID. When set, the principal is granted the Foundry User role so it can build agents and consume tools/toolboxes from the azd up baseline.')
param principalId string = ''

@description('Type of the deploying principal (User or ServicePrincipal). Provided automatically by azd as AZURE_PRINCIPAL_TYPE.')
@allowed([
  'User'
  'ServicePrincipal'
])
param principalType string = 'User'

@description('Name of the Cognitive Services account')
param cognitiveServicesName string = ''

@description('SKU name for the Cognitive Services account')
@allowed([
  'S0'
])
param cognitiveServicesSku string = 'S0'

@description('Name of the model deployment. Also used as the model/deployment id when creating agents (see docs/agent-creation.md).')
param modelDeploymentName string = 'gpt-5.4'

@description('Name of the model to deploy')
param modelName string = 'gpt-5.4'

@description('Version of the model to deploy. Availability varies by region; override if the default is not available in the target region.')
param modelVersion string = '2026-03-05'

@description('Format/publisher of the model to deploy')
param modelFormat string = 'OpenAI'

@description('SKU name for the model deployment')
param modelSkuName string = 'GlobalStandard'

@description('Capacity (in thousands of tokens per minute) for the model deployment')
param modelCapacity int = 50

@description('Name of the Cognitive Services project')
param projectName string = ''

@description('Display name for the Cognitive Services project')
param projectDisplayName string = 'Microsoft Foundry Project'

@description('Description for the Cognitive Services project')
param projectDescription string = ''

@description('Enable observability: a Log Analytics workspace + workspace-based Application Insights, connected to the project so agent runs are traceable in the Foundry portal.')
param enableObservability bool = true

@description('Retention (days) for the Log Analytics workspace')
@minValue(30)
param logAnalyticsRetentionInDays int = 30

@description('Enable the Azure AI Search RAG substrate: a Search service and a keyless (Entra ID) Foundry->Search connection, so an agent can be given the Azure AI Search tool for retrieval-augmented generation. The search index, documents, and the agent itself are data-plane objects created outside Bicep (see scripts/create-rag-agent.sh). Off by default.')
param enableAiSearch bool = false

@description('Name of the Azure AI Search service (only used when enableAiSearch is true)')
param searchServiceName string = ''

@description('SKU name for the Azure AI Search service')
@allowed([
  'basic'
  'standard'
])
param searchServiceSku string = 'basic'

@description('Name of the Foundry project connection to Azure AI Search')
param searchConnectionName string = 'aisearch'

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = {
  'azd-env-name': environmentName
}

// Cognitive Services - AIServices
resource cognitiveServices 'Microsoft.CognitiveServices/accounts@2026-05-01' = {
  name: !empty(cognitiveServicesName) ? cognitiveServicesName : '${abbrs.cognitiveServicesAccounts}${resourceToken}'
  location: location
  tags: tags
  kind: 'AIServices'
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: cognitiveServicesSku
  }
  properties: {
    customSubDomainName: !empty(cognitiveServicesName) ? cognitiveServicesName : '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    publicNetworkAccess: 'Enabled'
    allowProjectManagement: true
  }
}

// Model deployment so the azd up baseline is runnable end-to-end: the
// agent-creation flow (docs/agent-creation.md, scripts/create-agent.sh) creates
// an agent bound to a model and then runs it, which requires a deployed model.
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2026-05-01' = {
  parent: cognitiveServices
  name: modelDeploymentName
  sku: {
    name: modelSkuName
    capacity: modelCapacity
  }
  properties: {
    model: {
      format: modelFormat
      name: modelName
      version: modelVersion
    }
  }
}

// Cognitive Services Project
resource cognitiveServicesProject 'Microsoft.CognitiveServices/accounts/projects@2026-05-01' = {
  parent: cognitiveServices
  name: !empty(projectName) ? projectName : '${abbrs.cognitiveServicesAccounts}project-${resourceToken}'
  location: location
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    displayName: projectDisplayName
    description: projectDescription
  }
}

// Observability (conditional): a Log Analytics workspace + workspace-based
// Application Insights, connected to the project so agent runs are traceable in
// the Foundry portal's Traces view. Foundry does not provision an observability
// sink by default, so out of the box the Traces view is empty and prompts the
// user to connect an Application Insights resource. This wires that up.
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2026-03-01' = if (enableObservability) {
  name: '${abbrs.operationalInsightsWorkspaces}${resourceToken}'
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: logAnalyticsRetentionInDays
  }
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = if (enableObservability) {
  name: '${abbrs.insightsComponents}${resourceToken}'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: enableObservability ? logAnalytics.id : null
  }
}

// Foundry project connection to Application Insights (category AppInsights).
// Only one Application Insights connection can be set on a project at a time.
resource appInsightsConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2026-05-01' = if (enableObservability) {
  parent: cognitiveServicesProject
  name: 'appinsights'
  properties: {
    category: 'AppInsights'
    target: enableObservability ? applicationInsights.id : ''
    authType: 'ApiKey'
    isSharedToAll: true
    credentials: {
      key: enableObservability ? applicationInsights.properties.ConnectionString : ''
    }
    metadata: {
      ApiType: 'Azure'
      ResourceId: enableObservability ? applicationInsights.id : ''
    }
  }
}

// Azure AI Search RAG substrate (conditional). Bicep can provision the Search
// service, a keyless Foundry->Search connection, and the role assignments the
// project's managed identity needs to query the index. The index schema, the
// documents, and the agent that binds the azure_ai_search tool to this
// connection are Azure AI Search / Foundry *data-plane* objects and are created
// outside Bicep by scripts/create-rag-agent.sh. This split is inherent: a
// knowledge base / index is not an ARM resource.
resource searchService 'Microsoft.Search/searchServices@2025-05-01' = if (enableAiSearch) {
  name: !empty(searchServiceName) ? searchServiceName : '${abbrs.searchSearchServices}${resourceToken}'
  location: location
  tags: tags
  sku: {
    name: searchServiceSku
  }
  properties: {
    publicNetworkAccess: 'enabled'
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
  }
}

// Keyless (Entra ID) connection from the Foundry project to the Search service.
resource searchConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2026-05-01' = if (enableAiSearch) {
  parent: cognitiveServicesProject
  name: searchConnectionName
  properties: {
    category: 'CognitiveSearch'
    target: enableAiSearch ? 'https://${searchService.name}.search.windows.net' : ''
    authType: 'AAD'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
      ResourceId: enableAiSearch ? searchService.id : ''
    }
  }
}

// Grant the project's managed identity the roles it needs to query the index
// keylessly. Role: Search Index Data Contributor (8ebe5a00-799e-43f5-93ac-243d3dce84a7).
resource searchIndexDataRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableAiSearch) {
  scope: searchService
  name: guid(searchService.id, cognitiveServicesProject.id, '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
    principalId: enableAiSearch ? cognitiveServicesProject.identity.principalId : ''
    principalType: 'ServicePrincipal'
  }
}

// Role: Search Service Contributor (7ca78c08-252a-4471-8644-bb5ff32d4ba0).
resource searchServiceRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableAiSearch) {
  scope: searchService
  name: guid(searchService.id, cognitiveServicesProject.id, '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
    principalId: enableAiSearch ? cognitiveServicesProject.identity.principalId : ''
    principalType: 'ServicePrincipal'
  }
}

// Grant the deploying principal the Foundry User role on the account so the
// azd up baseline is usable end-to-end: building agents and consuming
// tools/toolboxes requires this data-plane role, which control-plane roles
// (for example, subscription Owner or Contributor) do not confer. The role
// inherits from the account to its projects.
// Role: Foundry User (53ca6127-db72-4b80-b1b0-d745d6d5456d)
resource foundryUserRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(principalId)) {
  scope: cognitiveServices
  name: guid(cognitiveServices.id, principalId, '53ca6127-db72-4b80-b1b0-d745d6d5456d')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '53ca6127-db72-4b80-b1b0-d745d6d5456d')
    principalId: principalId
    principalType: principalType
  }
}

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output COGNITIVE_SERVICES_NAME string = cognitiveServices.name
output COGNITIVE_SERVICES_ENDPOINT string = cognitiveServices.properties.endpoint
output MODEL_DEPLOYMENT_NAME string = modelDeployment.name
output PROJECT_NAME string = cognitiveServicesProject.name
output PROJECT_ENDPOINT string = 'https://${cognitiveServices.name}.services.ai.azure.com/api/projects/${cognitiveServicesProject.name}'
output APPLICATION_INSIGHTS_NAME string = enableObservability ? applicationInsights.name : ''
output LOG_ANALYTICS_WORKSPACE_NAME string = enableObservability ? logAnalytics.name : ''
output SEARCH_SERVICE_NAME string = enableAiSearch ? searchService.name : ''
output SEARCH_ENDPOINT string = enableAiSearch ? 'https://${searchService.name}.search.windows.net' : ''
output SEARCH_CONNECTION_NAME string = enableAiSearch ? searchConnectionName : ''
output SEARCH_CONNECTION_ID string = enableAiSearch ? searchConnection.id : ''
