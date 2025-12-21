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
param projectDisplayName string = 'AI Foundry Project'

@description('Description for the Cognitive Services project')
param projectDescription string = ''

@description('Enable application and agent deployment resources')
param enableAgentDeployments bool = false

@description('Name of the Cognitive Services application')
param applicationName string = ''

@description('Display name for the Cognitive Services application')
param applicationDisplayName string = 'AI Foundry Application'

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

@description('Minimum replicas for Hosted deployment type')
@minValue(1)
param agentDeploymentMinReplicas int = 1

@description('Maximum replicas for Hosted deployment type')
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
resource cognitiveServicesApplication 'Microsoft.CognitiveServices/accounts/projects/applications@2025-10-01-preview' = if (enableAgentDeployments) {
  parent: cognitiveServicesProject
  name: !empty(applicationName) ? applicationName : '${abbrs.cognitiveServicesApplications}${resourceToken}'
  properties: {
    displayName: applicationDisplayName
    description: applicationDescription
  }
}

// Agent Deployment (conditional)
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
output APPLICATION_NAME string = enableAgentDeployments ? cognitiveServicesApplication.name : ''
output AGENT_DEPLOYMENT_NAME string = enableAgentDeployments ? agentDeployment.name : ''
