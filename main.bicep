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
var apimName = '${baseName}-apim'
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
// API Management
// ============================================================================

module apim 'modules/apim/apim.bicep' = {
  scope: resourceGroup
  name: 'deploy-apim'
  dependsOn: [aoaiPrimary, aoaiSecondary]
  params: {
    name: apimName
    location: primaryLocation
    publisherEmail: apimPublisherEmail
    publisherName: apimPublisherName
    tags: tags
    skuName: 'Premium'
    skuCapacity: 1
    aoaiPrimaryEndpoint: aoaiPrimary.outputs.endpoint
    aoaiSecondaryEndpoint: aoaiSecondary.outputs.endpoint
  }
}

// ============================================================================
// Role Assignment - APIM to Azure OpenAI (Primary)
// ============================================================================

module roleAssignmentPrimary 'modules/rbac/cognitive-services-user.bicep' = {
  scope: resourceGroup
  name: 'deploy-role-assignment-primary'
  dependsOn: [apim, aoaiPrimary]
  params: {
    principalId: apim.outputs.principalId
    cognitiveServicesAccountName: aoaiPrimaryName
  }
}

// ============================================================================
// Role Assignment - APIM to Azure OpenAI (Secondary)
// ============================================================================

module roleAssignmentSecondary 'modules/rbac/cognitive-services-user.bicep' = {
  scope: resourceGroup
  name: 'deploy-role-assignment-secondary'
  dependsOn: [apim, aoaiSecondary]
  params: {
    principalId: apim.outputs.principalId
    cognitiveServicesAccountName: aoaiSecondaryName
  }
}

// ============================================================================
// Azure Front Door
// ============================================================================

module frontDoor 'modules/frontdoor/frontdoor.bicep' = {
  scope: resourceGroup
  name: 'deploy-frontdoor'
  dependsOn: [apim]
  params: {
    name: frontDoorName
    tags: tags
    apimPrimaryGatewayUrl: apim.outputs.gatewayUrl
    apimSecondaryGatewayUrl: apim.outputs.gatewayUrl // Same APIM with multi-region
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

@description('API Management gateway URL')
output apimGatewayUrl string = apim.outputs.gatewayUrl

@description('API Management developer portal URL')
output apimDeveloperPortalUrl string = apim.outputs.developerPortalUrl

@description('Front Door endpoint URL')
output frontDoorEndpointUrl string = frontDoor.outputs.endpointUrl

@description('APIM Principal ID (for role assignments)')
output apimPrincipalId string = apim.outputs.principalId
