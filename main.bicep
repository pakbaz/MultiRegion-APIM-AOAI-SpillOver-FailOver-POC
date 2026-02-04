// ============================================================================
// Main Bicep Template
// Multi-Region Azure APIM + AOAI Architecture with Front Door
// ============================================================================

targetScope = 'subscription'

// ============================================================================
// Parameters
// ============================================================================

@description('Base name for all resources. Must be globally unique as it is used in DNS names.')
param baseName string

@description('Primary Azure region')
param primaryLocation string = 'eastus'

@description('Secondary Azure region')
param secondaryLocation string = 'westus'

@description('Publisher email for APIM')
param apimPublisherEmail string

@description('Publisher name for APIM')
param apimPublisherName string

@description('Tags to apply to all resources')
param tags object = {
  project: 'APIM-AOAI-Multi-Region'
  environment: 'poc'
}

@description('Primary deployment capacity for GPT-4o (low for testing spillover)')
param gpt4oPrimaryCapacity int = 10

@description('Primary deployment capacity for GPT-4o-mini (low for testing spillover)')
param gpt4oMiniPrimaryCapacity int = 10

@description('Spillover capacity for GPT-4o (TPM in thousands)')
param gpt4oSpilloverCapacity int = 80

@description('Spillover capacity for GPT-4o-mini (TPM in thousands)')
param gpt4oMiniSpilloverCapacity int = 80

// ============================================================================
// Variables
// ============================================================================

var resourceGroupName = 'rg-${baseName}'
var aoaiPrimaryName = '${baseName}-aoai-${primaryLocation}'
var aoaiSecondaryName = '${baseName}-aoai-${secondaryLocation}'
var apimPrimaryName = '${baseName}-apim-${primaryLocation}'
var apimSecondaryName = '${baseName}-apim-${secondaryLocation}'
var frontDoorName = '${baseName}-fd'

// ============================================================================
// Resource Group
// ============================================================================

resource resourceGroup 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: resourceGroupName
  location: primaryLocation
  tags: tags
}

// ============================================================================
// Azure OpenAI - Primary Region
// ============================================================================

module aoaiPrimary 'modules/aoai/aoai.bicep' = {
  scope: resourceGroup
  name: 'deploy-aoai-primary'
  params: {
    name: aoaiPrimaryName
    location: primaryLocation
    tags: union(tags, { region: primaryLocation })
    gpt4oPrimaryCapacity: gpt4oPrimaryCapacity
    gpt4oMiniPrimaryCapacity: gpt4oMiniPrimaryCapacity
    gpt4oSpilloverCapacity: gpt4oSpilloverCapacity
    gpt4oMiniSpilloverCapacity: gpt4oMiniSpilloverCapacity
  }
}

// ============================================================================
// Azure OpenAI - Secondary Region
// ============================================================================

module aoaiSecondary 'modules/aoai/aoai.bicep' = {
  scope: resourceGroup
  name: 'deploy-aoai-secondary'
  params: {
    name: aoaiSecondaryName
    location: secondaryLocation
    tags: union(tags, { region: secondaryLocation })
    gpt4oPrimaryCapacity: gpt4oPrimaryCapacity
    gpt4oMiniPrimaryCapacity: gpt4oMiniPrimaryCapacity
    gpt4oSpilloverCapacity: gpt4oSpilloverCapacity
    gpt4oMiniSpilloverCapacity: gpt4oMiniSpilloverCapacity
  }
}

// ============================================================================
// API Management - Primary Region
// ============================================================================

module apimPrimary 'modules/apim/apim.bicep' = {
  scope: resourceGroup
  name: 'deploy-apim-primary'
  params: {
    name: apimPrimaryName
    location: primaryLocation
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    tags: union(tags, { region: primaryLocation })
    skuName: 'Standard'
    skuCapacity: 1
    aoaiPrimaryEndpoint: aoaiPrimary.outputs.endpoint
    aoaiSecondaryEndpoint: aoaiSecondary.outputs.endpoint
  }
}

// ============================================================================
// API Management - Secondary Region
// ============================================================================

module apimSecondary 'modules/apim/apim.bicep' = {
  scope: resourceGroup
  name: 'deploy-apim-secondary'
  params: {
    name: apimSecondaryName
    location: secondaryLocation
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    tags: union(tags, { region: secondaryLocation })
    skuName: 'Standard'
    skuCapacity: 1
    aoaiPrimaryEndpoint: aoaiPrimary.outputs.endpoint
    aoaiSecondaryEndpoint: aoaiSecondary.outputs.endpoint
  }
}

// ============================================================================
// Role Assignments - Primary APIM to Azure OpenAI (both regions)
// ============================================================================

module roleAssignmentPrimaryApimToPrimaryAoai 'modules/rbac/cognitive-services-user.bicep' = {
  scope: resourceGroup
  name: 'deploy-role-primary-apim-primary-aoai'
  params: {
    principalId: apimPrimary.outputs.principalId
    cognitiveServicesAccountName: aoaiPrimaryName
  }
}

module roleAssignmentPrimaryApimToSecondaryAoai 'modules/rbac/cognitive-services-user.bicep' = {
  scope: resourceGroup
  name: 'deploy-role-primary-apim-secondary-aoai'
  params: {
    principalId: apimPrimary.outputs.principalId
    cognitiveServicesAccountName: aoaiSecondaryName
  }
}

// ============================================================================
// Role Assignments - Secondary APIM to Azure OpenAI (both regions)
// ============================================================================

module roleAssignmentSecondaryApimToPrimaryAoai 'modules/rbac/cognitive-services-user.bicep' = {
  scope: resourceGroup
  name: 'deploy-role-secondary-apim-primary-aoai'
  params: {
    principalId: apimSecondary.outputs.principalId
    cognitiveServicesAccountName: aoaiPrimaryName
  }
}

module roleAssignmentSecondaryApimToSecondaryAoai 'modules/rbac/cognitive-services-user.bicep' = {
  scope: resourceGroup
  name: 'deploy-role-secondary-apim-secondary-aoai'
  params: {
    principalId: apimSecondary.outputs.principalId
    cognitiveServicesAccountName: aoaiSecondaryName
  }
}

// ============================================================================
// Azure Front Door
// ============================================================================

module frontDoor 'modules/frontdoor/frontdoor.bicep' = {
  scope: resourceGroup
  name: 'deploy-frontdoor'
  params: {
    name: frontDoorName
    tags: tags
    apimPrimaryGatewayUrl: apimPrimary.outputs.gatewayUrl
    apimSecondaryGatewayUrl: apimSecondary.outputs.gatewayUrl
    primaryRegionName: primaryLocation
    secondaryRegionName: secondaryLocation
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource Group name')
output resourceGroupName string = resourceGroup.name

@description('Azure OpenAI Primary endpoint')
output aoaiPrimaryEndpoint string = aoaiPrimary.outputs.endpoint

@description('Azure OpenAI Secondary endpoint')
output aoaiSecondaryEndpoint string = aoaiSecondary.outputs.endpoint

@description('API Management Primary gateway URL')
output apimPrimaryGatewayUrl string = apimPrimary.outputs.gatewayUrl

@description('API Management Secondary gateway URL')
output apimSecondaryGatewayUrl string = apimSecondary.outputs.gatewayUrl

@description('API Management Primary developer portal URL')
output apimPrimaryDeveloperPortalUrl string = apimPrimary.outputs.developerPortalUrl

@description('API Management Secondary developer portal URL')
output apimSecondaryDeveloperPortalUrl string = apimSecondary.outputs.developerPortalUrl

@description('Front Door endpoint URL')
output frontDoorEndpointUrl string = frontDoor.outputs.endpointUrl

@description('APIM Primary Principal ID')
output apimPrimaryPrincipalId string = apimPrimary.outputs.principalId

@description('APIM Secondary Principal ID')
output apimSecondaryPrincipalId string = apimSecondary.outputs.principalId
