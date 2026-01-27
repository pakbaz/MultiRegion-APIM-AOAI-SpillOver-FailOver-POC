// ============================================================================
// Azure OpenAI Module
// Deploys Azure OpenAI account with Standard (Pay-as-you-go) model deployments
// Simulates PTU vs PAYG with primary (low capacity) and spillover (higher capacity)
// ============================================================================

@description('Name of the Azure OpenAI resource')
param name string

@description('Location for the resource')
param location string

@description('Tags to apply to the resource')
param tags object = {}

@description('Custom subdomain name for the OpenAI endpoint')
param customSubDomainName string = name

@description('Whether to enable public network access')
@allowed(['Enabled', 'Disabled'])
param publicNetworkAccess string = 'Enabled'

@description('Capacity for GPT-4o primary deployment (low capacity for spillover testing)')
param gpt4oPrimaryCapacity int = 10

@description('Capacity for GPT-4o-mini primary deployment (low capacity for spillover testing)')
param gpt4oMiniPrimaryCapacity int = 10

@description('Capacity for GPT-4o spillover deployment (higher capacity)')
param gpt4oSpilloverCapacity int = 80

@description('Capacity for GPT-4o-mini spillover deployment (higher capacity)')
param gpt4oMiniSpilloverCapacity int = 80

// ============================================================================
// Azure OpenAI Account
// ============================================================================

resource openAI 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: name
  location: location
  tags: tags
  kind: 'OpenAI'
  sku: {
    name: 'S0'
  }
  properties: {
    customSubDomainName: customSubDomainName
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
  }
}

// ============================================================================
// Model Deployments - Primary (Low Capacity - simulating constrained throughput)
// Small capacity for testing exhaustion/spillover scenarios
// ============================================================================

resource gpt4oPrimary 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAI
  name: 'gpt-4o-primary'
  sku: {
    name: 'GlobalStandard'
    capacity: gpt4oPrimaryCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-08-06'
    }
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

resource gpt4oMiniPrimary 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAI
  name: 'gpt-4o-mini-primary'
  dependsOn: [gpt4oPrimary]
  sku: {
    name: 'GlobalStandard'
    capacity: gpt4oMiniPrimaryCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o-mini'
      version: '2024-07-18'
    }
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

// ============================================================================
// Model Deployments - Spillover (Higher Capacity)
// ============================================================================

resource gpt4oSpillover 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAI
  name: 'gpt-4o-spillover'
  dependsOn: [gpt4oMiniPrimary]
  sku: {
    name: 'GlobalStandard'
    capacity: gpt4oSpilloverCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o'
      version: '2024-08-06'
    }
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

resource gpt4oMiniSpillover 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  parent: openAI
  name: 'gpt-4o-mini-spillover'
  dependsOn: [gpt4oSpillover]
  sku: {
    name: 'GlobalStandard'
    capacity: gpt4oMiniSpilloverCapacity
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: 'gpt-4o-mini'
      version: '2024-07-18'
    }
    raiPolicyName: 'Microsoft.DefaultV2'
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource ID of the Azure OpenAI account')
output id string = openAI.id

@description('Name of the Azure OpenAI account')
output name string = openAI.name

@description('Endpoint URL of the Azure OpenAI account')
output endpoint string = openAI.properties.endpoint

@description('Primary deployment names (low capacity)')
output primaryDeployments object = {
  gpt4o: gpt4oPrimary.name
  gpt4oMini: gpt4oMiniPrimary.name
}

@description('Spillover deployment names (higher capacity)')
output spilloverDeployments object = {
  gpt4o: gpt4oSpillover.name
  gpt4oMini: gpt4oMiniSpillover.name
}
