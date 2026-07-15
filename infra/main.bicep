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

@description('Optional plain-text purpose tag for resources created by this azd environment. Do not put secrets or private deployment details here.')
param environmentPurpose string = ''

@description('Optional plain-text lifecycle tag for resources created by this azd environment, for example ephemeral or persistent.')
param environmentLifecycle string = ''

@description('Optional plain-text workstream tag for resources created by this azd environment.')
param environmentWorkstream string = ''

@description('Optional service principal object ID for the GitHub Actions OIDC identity that queries aggregate Foundry Guide feedback. When set, observability must be enabled and this principal gets monitoring read roles on the telemetry resources.')
param foundryGuideFeedbackPrincipalId string = ''

@description('Enable the authenticated Foundry Guide browser client hosted as one Linux Azure App Service web app.')
param enableFoundryGuideWebApp bool = false

@minLength(1)
@description('Name of the Foundry Guide prompt agent served by the web application.')
param foundryGuideAgentName string = 'foundry-guide'

@description('Microsoft Entra application client ID for the Foundry Guide web SPA/API.')
param foundryGuideWebAuthClientId string = ''

@allowed([
  'B1'
  'B2'
  'B3'
])
@description('Dedicated Linux App Service plan SKU for the Foundry Guide web app.')
param foundryGuideWebAppServiceSku string = 'B1'

@description('Retention (days) for the Log Analytics workspace')
@minValue(30)
param logAnalyticsRetentionInDays int = 30

@description('Enable the Foundry IQ substrate: an Azure AI Search service, a keyless (project managed identity) RemoteTool connection to the knowledge base MCP endpoint, and the Search role the project needs to run retrieval. The index, documents, knowledge source, knowledge base, and agent are Azure AI Search / Foundry data-plane objects created post-provisioning (see scripts/foundry-iq-setup.sh, wired as an azd postprovision hook). Off by default.')
param enableFoundryIq bool = false

@description('Name of the Azure AI Search service (only used when enableFoundryIq is true)')
param searchServiceName string = ''

@description('SKU name for the Azure AI Search service. Basic or higher is required for agentic retrieval with a managed identity.')
@allowed([
  'basic'
  'standard'
])
param searchServiceSku string = 'basic'

@description('Name of the Foundry IQ knowledge base. The RemoteTool connection targets this knowledge base MCP endpoint; scripts/foundry-iq-setup.sh must create a knowledge base with this same name.')
param knowledgeBaseName string = 'kb-foundry-iq'

@description('Azure AI Search REST API version used in the knowledge base MCP endpoint. 2026-04-01 is the generally available, extractive agentic-retrieval API; 2026-05-01-preview adds server-side answer synthesis but then requires an Azure OpenAI model on the knowledge base.')
param searchApiVersion string = '2026-04-01'

@description('Name of the Foundry project RemoteTool connection to the knowledge base MCP endpoint')
param knowledgeBaseConnectionName string = 'foundry-iq-kb'

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var deployFoundryGuideWebApp = enableFoundryGuideWebApp && !empty(foundryGuideWebAuthClientId)
var tags = union(
  {
    'azd-env-name': environmentName
  },
  !empty(environmentPurpose) ? {
    'environment-purpose': environmentPurpose
  } : {},
  !empty(environmentLifecycle) ? {
    'environment-lifecycle': environmentLifecycle
  } : {},
  !empty(environmentWorkstream) ? {
    'environment-workstream': environmentWorkstream
  } : {}
)

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
      key: enableObservability ? applicationInsights!.properties.ConnectionString : ''
    }
    metadata: {
      ApiType: 'Azure'
      ResourceId: enableObservability ? applicationInsights.id : ''
    }
  }
}

// Let the deploying principal run the workspace-scoped diagnostics used to
// verify trace and evaluation ingestion.
// Role: Log Analytics Reader (73c42c96-874c-492b-b04d-ab87d138a893)
resource observabilityLogAnalyticsReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableObservability && !empty(principalId)) {
  scope: logAnalytics
  name: guid(logAnalytics.id, principalId, '73c42c96-874c-492b-b04d-ab87d138a893')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893')
    principalId: principalId
    principalType: principalType
  }
}

// Optional secretless GitHub Actions path for issue automation. The workflow
// queries aggregate feedback only, so read-only monitoring roles are enough.
// Role: Monitoring Reader (43d0d8ad-25c7-4714-9337-8ba259a9fe05)
resource feedbackAppInsightsMonitoringReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableObservability && !empty(foundryGuideFeedbackPrincipalId)) {
  scope: applicationInsights
  name: guid(applicationInsights.id, foundryGuideFeedbackPrincipalId, '43d0d8ad-25c7-4714-9337-8ba259a9fe05')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '43d0d8ad-25c7-4714-9337-8ba259a9fe05')
    principalId: foundryGuideFeedbackPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Role: Log Analytics Reader (73c42c96-874c-492b-b04d-ab87d138a893)
resource feedbackLogAnalyticsReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableObservability && !empty(foundryGuideFeedbackPrincipalId) && toLower(foundryGuideFeedbackPrincipalId) != toLower(principalId)) {
  scope: logAnalytics
  name: guid(logAnalytics.id, foundryGuideFeedbackPrincipalId, '73c42c96-874c-492b-b04d-ab87d138a893')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '73c42c96-874c-492b-b04d-ab87d138a893')
    principalId: foundryGuideFeedbackPrincipalId
    principalType: 'ServicePrincipal'
  }
}

// Optional authenticated browser client for Foundry Guide. One Linux App Service
// serves both the SPA and API, validates tokens from the resource subscription's
// tenant, and calls Foundry through its managed identity.
resource foundryGuideWebPlan 'Microsoft.Web/serverfarms@2026-03-15' = if (deployFoundryGuideWebApp) {
  name: '${abbrs.webServerFarms}${resourceToken}'
  location: location
  tags: tags
  kind: 'linux'
  sku: {
    name: foundryGuideWebAppServiceSku
    tier: 'Basic'
  }
  properties: {
    reserved: true
  }
}

resource foundryGuideWebApp 'Microsoft.Web/sites@2026-03-15' = if (deployFoundryGuideWebApp) {
  name: '${abbrs.webSitesApp}${resourceToken}'
  location: location
  tags: tags
  kind: 'app,linux'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    clientAffinityEnabled: false
    httpsOnly: true
    publicNetworkAccess: 'Enabled'
    serverFarmId: foundryGuideWebPlan.id
    siteConfig: {
      alwaysOn: true
      appSettings: [
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: enableObservability ? applicationInsights!.properties.ConnectionString : ''
        }
        {
          name: 'AUTH_CLIENT_ID'
          value: foundryGuideWebAuthClientId
        }
        {
          name: 'AUTH_TENANT_ID'
          value: tenant().tenantId
        }
        {
          name: 'FOUNDRY_GUIDE_AGENT_NAME'
          value: foundryGuideAgentName
        }
        {
          name: 'FOUNDRY_GUIDE_AGENT_VERSION'
          value: 'active'
        }
        {
          name: 'OTEL_SERVICE_NAME'
          value: 'foundry-guide-web'
        }
        {
          name: 'PROJECT_ENDPOINT'
          value: 'https://${cognitiveServices.name}.services.ai.azure.com/api/projects/${cognitiveServicesProject.name}'
        }
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
      ]
      ftpsState: 'Disabled'
      healthCheckPath: '/health'
      http20Enabled: true
      linuxFxVersion: 'DOTNETCORE|10.0'
      minTlsVersion: '1.2'
      scmMinTlsVersion: '1.2'
    }
  }
}

resource foundryGuideWebFtpPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2026-03-15' = if (deployFoundryGuideWebApp) {
  parent: foundryGuideWebApp
  name: 'ftp'
  properties: {
    allow: false
  }
}

resource foundryGuideWebScmPolicy 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2026-03-15' = if (deployFoundryGuideWebApp) {
  parent: foundryGuideWebApp
  name: 'scm'
  properties: {
    allow: false
  }
}

// Role: Foundry Agent Consumer (eed3b665-ab3a-47b6-8f48-c9382fb1dad6)
resource foundryGuideWebConsumerRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployFoundryGuideWebApp) {
  scope: cognitiveServicesProject
  name: guid(cognitiveServicesProject.id, foundryGuideWebApp.id, 'eed3b665-ab3a-47b6-8f48-c9382fb1dad6')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'eed3b665-ab3a-47b6-8f48-c9382fb1dad6')
    principalId: foundryGuideWebApp!.identity.principalId
    principalType: 'ServicePrincipal'
  }
}

// Foundry IQ substrate (conditional). Bicep can provision the Azure AI Search
// service, the RemoteTool connection the project uses to reach the knowledge
// base's MCP endpoint, and the Search role the project's managed identity needs
// to run retrieval. The index, documents, knowledge source, knowledge base, and
// the agent are Azure AI Search / Foundry *data-plane* objects created after
// provisioning by scripts/foundry-iq-setup.sh (an azd postprovision hook). This
// split is inherent: a knowledge base is not an ARM resource.
resource searchService 'Microsoft.Search/searchServices@2025-05-01' = if (enableFoundryIq) {
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

// Keyless RemoteTool connection from the Foundry project to the knowledge base's
// MCP endpoint, authenticated by the project's managed identity. The target is a
// URL string, so this connection can be created before the knowledge base
// exists (the knowledge base is created post-provisioning).
// Note: `audience` must be https://search.azure.com with NO trailing slash, or
// the agent's runtime token fetch fails with "Missing required query parameter
// 'audience'".
// This wires the generally available, extractive path (searchApiVersion
// 2026-04-01). Server-side answer synthesis (2026-05-01-preview) would also
// require the Search service to have a managed identity with Cognitive Services
// OpenAI User on the Foundry account, plus a model on the knowledge base.
resource knowledgeBaseConnection 'Microsoft.CognitiveServices/accounts/projects/connections@2026-05-01' = if (enableFoundryIq) {
  parent: cognitiveServicesProject
  name: knowledgeBaseConnectionName
  properties: {
    category: 'RemoteTool'
    authType: 'ProjectManagedIdentity'
    target: enableFoundryIq ? 'https://${searchService.name}.search.windows.net/knowledgebases/${knowledgeBaseName}/mcp?api-version=${searchApiVersion}' : ''
    audience: 'https://search.azure.com'
    isSharedToAll: true
    metadata: {
      ApiType: 'Azure'
    }
  }
}

// Grant the project's managed identity the role it needs to run knowledge base
// retrieval keylessly. Role: Search Index Data Reader (1407120a-92aa-4202-b7e9-c0e197c71c8f).
resource searchIndexDataReaderRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableFoundryIq) {
  scope: searchService
  name: guid(searchService.id, cognitiveServicesProject.id, '1407120a-92aa-4202-b7e9-c0e197c71c8f')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '1407120a-92aa-4202-b7e9-c0e197c71c8f')
    principalId: enableFoundryIq ? cognitiveServicesProject.identity.principalId : ''
    principalType: 'ServicePrincipal'
  }
}

// Grant the deploying principal the two Search data-plane roles the
// post-provisioning hook (scripts/foundry-iq-setup.sh) needs to build the
// knowledge base substrate keylessly (Entra token, no admin key):
//   Search Service Contributor (7ca78c08-252a-4471-8644-bb5ff32d4ba0) — create
//     the index, knowledge source, and knowledge base definitions.
//   Search Index Data Contributor (8ebe5a00-799e-43f5-93ac-243d3dce84a7) —
//     upload the sample documents.
resource searchServiceContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableFoundryIq && !empty(principalId)) {
  scope: searchService
  name: guid(searchService.id, principalId, '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7ca78c08-252a-4471-8644-bb5ff32d4ba0')
    principalId: principalId
    principalType: principalType
  }
}

resource searchIndexDataContributorRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (enableFoundryIq && !empty(principalId)) {
  scope: searchService
  name: guid(searchService.id, principalId, '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '8ebe5a00-799e-43f5-93ac-243d3dce84a7')
    principalId: principalId
    principalType: principalType
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
output SEARCH_SERVICE_NAME string = enableFoundryIq ? searchService.name : ''
output SEARCH_ENDPOINT string = enableFoundryIq ? 'https://${searchService.name}.search.windows.net' : ''
output ENABLE_FOUNDRY_IQ bool = enableFoundryIq
output KNOWLEDGE_BASE_NAME string = enableFoundryIq ? knowledgeBaseName : ''
output KNOWLEDGE_BASE_CONNECTION_NAME string = enableFoundryIq ? knowledgeBaseConnectionName : ''
output SEARCH_API_VERSION string = enableFoundryIq ? searchApiVersion : ''
output FOUNDRY_GUIDE_WEB_APP_NAME string = deployFoundryGuideWebApp ? foundryGuideWebApp.name : ''
output FOUNDRY_GUIDE_WEB_APP_URL string = deployFoundryGuideWebApp ? 'https://${foundryGuideWebApp!.properties.defaultHostName}' : ''
