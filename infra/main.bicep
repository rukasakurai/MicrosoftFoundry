targetScope = 'resourceGroup'

@minLength(1)
@maxLength(64)
@description('Name of the environment that can be used as part of naming resource convention')
param environmentName string

@minLength(1)
@description('Primary location for all resources')
param location string

@description('Name of the Cognitive Services account')
param cognitiveServicesName string = ''

@description('SKU name for the Cognitive Services account')
@allowed([
  'S0'
])
param cognitiveServicesSku string = 'S0'

@description('Name of the Cognitive Services project')
param projectName string = ''

@description('Display name for the Cognitive Services project')
param projectDisplayName string = 'Microsoft Foundry Project'

@description('Description for the Cognitive Services project')
param projectDescription string = ''

@description('Name of the model deployment')
param modelDeploymentName string = 'gpt-5.4-mini'

@description('Model name to deploy')
param modelName string = 'gpt-5.4-mini'

@description('Model version to deploy')
param modelVersion string = '2026-03-17'

@description('SKU name for the model deployment')
@allowed([
  'GlobalStandard'
  'DataZoneStandard'
  'Standard'
])
param modelDeploymentSkuName string = 'GlobalStandard'

@description('Capacity for the model deployment (in thousands of tokens per minute)')
param modelDeploymentCapacity int = 10

@description('Enable application and agent deployment resources')
param enableAgentDeployments bool = false

@description('Name of the Cognitive Services application')
param applicationName string = ''

@description('Display name for the Cognitive Services application')
param applicationDisplayName string = 'Microsoft Foundry Application'

@description('Description for the Cognitive Services application')
param applicationDescription string = ''

@description('Name of the agent deployment')
param agentDeploymentName string = ''

@description('Display name for the agent deployment')
param agentDeploymentDisplayName string = 'Agent Deployment'

@description('Description for the agent deployment')
param agentDeploymentDescription string = ''

@description('Deployment type for the agent deployment')
@allowed([
  'Managed'
  'Hosted'
])
param agentDeploymentType string = 'Managed'

@description('Minimum replicas for Hosted deployment type. Must be less than or equal to agentDeploymentMaxReplicas.')
@minValue(1)
param agentDeploymentMinReplicas int = 1

@description('Maximum replicas for Hosted deployment type. Must be greater than or equal to agentDeploymentMinReplicas.')
@minValue(1)
param agentDeploymentMaxReplicas int = 3

var abbrs = loadJsonContent('./abbreviations.json')
var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = {
  'azd-env-name': environmentName
}

// Cognitive Services - AIServices
resource cognitiveServices 'Microsoft.CognitiveServices/accounts@2025-10-01-preview' = {
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

// Model Deployment (e.g., GPT-5 series)
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-10-01-preview' = {
  parent: cognitiveServices
  name: modelDeploymentName
  sku: {
    name: modelDeploymentSkuName
    capacity: modelDeploymentCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      version: modelVersion
    }
  }
}

// Cognitive Services Project
resource cognitiveServicesProject 'Microsoft.CognitiveServices/accounts/projects@2025-10-01-preview' = {
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

// Cognitive Services Application (conditional)
// NOTE: This resource creates the infrastructure to PUBLISH agents, not to create them.
// An application provides:
// - A stable endpoint URL for external consumers
// - A unique identity (separate from project identity) with its own RBAC and audit trail
// - User data isolation between consumers
// - SaaS-like behavior for sharing agents externally
// You must first create an agent in the Foundry portal or via SDK, then publish it to this application.
resource cognitiveServicesApplication 'Microsoft.CognitiveServices/accounts/projects/applications@2025-10-01-preview' = if (enableAgentDeployments) {
  parent: cognitiveServicesProject
  name: !empty(applicationName) ? applicationName : '${abbrs.cognitiveServicesApplications}${resourceToken}'
  properties: {
    displayName: applicationDisplayName
    description: applicationDescription
  }
}

// Agent Deployment (conditional)
// NOTE: This resource creates a RUNNING INSTANCE to host a published agent, not the agent itself.
// A deployment:
// - Routes traffic from the application endpoint to a specific agent version
// - Requires an agent to be created first (via portal or SDK) and then referenced in the 'agents' property
// - Supports 'Managed' (Azure manages infrastructure) or 'Hosted' (custom scaling with replicas)
// 
// IMPORTANT: This deployment is created WITHOUT an agent reference. To make it functional:
// 1. Create an agent in the Foundry portal (Agents > Create agent) or via SDK
// 2. Update this deployment via REST API to include: agents: [{ agentName: '...', agentVersion: '...' }]
// Or publish the agent directly from the Foundry portal which creates the application and deployment automatically.
resource agentDeployment 'Microsoft.CognitiveServices/accounts/projects/applications/agentDeployments@2025-10-01-preview' = if (enableAgentDeployments) {
  parent: cognitiveServicesApplication
  name: !empty(agentDeploymentName) ? agentDeploymentName : '${abbrs.cognitiveServicesAgentDeployments}${resourceToken}'
  properties: {
    displayName: agentDeploymentDisplayName
    description: agentDeploymentDescription
    deploymentType: agentDeploymentType
    minReplicas: agentDeploymentType == 'Hosted' ? agentDeploymentMinReplicas : null
    maxReplicas: agentDeploymentType == 'Hosted' ? agentDeploymentMaxReplicas : null
  }
}

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output COGNITIVE_SERVICES_NAME string = cognitiveServices.name
output COGNITIVE_SERVICES_ENDPOINT string = cognitiveServices.properties.endpoint
output PROJECT_NAME string = cognitiveServicesProject.name
output PROJECT_ENDPOINT string = 'https://${cognitiveServices.name}.services.ai.azure.com/api/projects/${cognitiveServicesProject.name}'
output MODEL_DEPLOYMENT_NAME string = modelDeployment.name
output APPLICATION_NAME string = cognitiveServicesApplication.?name ?? ''
output AGENT_DEPLOYMENT_NAME string = agentDeployment.?name ?? ''
