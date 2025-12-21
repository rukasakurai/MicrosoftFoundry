@description('Name of the Cognitive Services account')
param name string

@description('Location for the resource')
param location string

@description('Tags for the resource')
param tags object = {}

@description('SKU name for the Cognitive Services account')
@allowed([
  'S0'
])
param sku string = 'S0'

resource cognitiveServices 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: name
  location: location
  tags: tags
  kind: 'AIServices'
  sku: {
    name: sku
  }
  properties: {
    customSubDomainName: name
    publicNetworkAccess: 'Enabled'
  }
}

output name string = cognitiveServices.name
output endpoint string = cognitiveServices.properties.endpoint
output id string = cognitiveServices.id
