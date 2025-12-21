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

output AZURE_LOCATION string = location
output AZURE_TENANT_ID string = tenant().tenantId
output COGNITIVE_SERVICES_NAME string = cognitiveServices.name
output COGNITIVE_SERVICES_ENDPOINT string = cognitiveServices.properties.endpoint
output PROJECT_NAME string = cognitiveServicesProject.name
