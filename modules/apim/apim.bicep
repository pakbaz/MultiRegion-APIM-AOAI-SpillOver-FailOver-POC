// ============================================================================
// Azure API Management Module
// Deploys APIM with backend pools for Azure OpenAI (PTU + PAYG spillover)
// ============================================================================

@description('Name of the API Management service')
param name string

@description('Primary location for APIM')
param location string

@description('Publisher email for APIM')
param publisherEmail string

@description('Publisher name for APIM')
param publisherName string

@description('Tags to apply to the resource')
param tags object = {}

@description('SKU name for APIM (Premium required for multi-region)')
@allowed(['Developer', 'Basic', 'Standard', 'Premium'])
param skuName string = 'Premium'

@description('SKU capacity (number of units)')
param skuCapacity int = 1

@description('Azure OpenAI endpoint URL for the primary region')
param aoaiPrimaryEndpoint string

@description('Azure OpenAI endpoint URL for the secondary region')
param aoaiSecondaryEndpoint string

@description('Azure OpenAI PTU deployment name for GPT-4o')
param gpt4oPtuDeployment string = 'gpt-4o-ptu'

@description('Azure OpenAI standard deployment name for GPT-4o')
param gpt4oStandardDeployment string = 'gpt-4o-standard'

@description('Azure OpenAI PTU deployment name for GPT-4o-mini')
param gpt4oMiniPtuDeployment string = 'gpt-4o-mini-ptu'

@description('Azure OpenAI standard deployment name for GPT-4o-mini')
param gpt4oMiniStandardDeployment string = 'gpt-4o-mini-standard'

@description('Managed identity resource ID for Azure OpenAI access (optional)')
param managedIdentityId string = ''

// ============================================================================
// API Management Service
// ============================================================================

resource apim 'Microsoft.ApiManagement/service@2023-09-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: skuName
    capacity: skuCapacity
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: 'None'
  }
}

// ============================================================================
// Named Values for Azure OpenAI Configuration
// ============================================================================

resource namedValueAoaiPrimaryEndpoint 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'aoai-primary-endpoint'
  properties: {
    displayName: 'aoai-primary-endpoint'
    value: aoaiPrimaryEndpoint
    secret: false
  }
}

resource namedValueAoaiSecondaryEndpoint 'Microsoft.ApiManagement/service/namedValues@2023-09-01-preview' = {
  parent: apim
  name: 'aoai-secondary-endpoint'
  properties: {
    displayName: 'aoai-secondary-endpoint'
    value: aoaiSecondaryEndpoint
    secret: false
  }
}

// ============================================================================
// Backends - Primary Region (PTU + Standard)
// ============================================================================

// GPT-4o PTU Backend (Primary)
resource backendGpt4oPtuPrimary 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'aoai-gpt4o-ptu-primary'
  properties: {
    title: 'Azure OpenAI GPT-4o PTU (Primary Region)'
    description: 'PTU deployment for GPT-4o in primary region'
    url: '${aoaiPrimaryEndpoint}openai'
    protocol: 'http'
    circuitBreaker: {
      rules: [
        {
          name: 'ptuThrottlingRule'
          failureCondition: {
            count: 3
            errorReasons: ['Timeout']
            interval: 'PT10S'
            statusCodeRanges: [
              { min: 429, max: 429 }
              { min: 500, max: 599 }
            ]
          }
          tripDuration: 'PT1M'
          acceptRetryAfter: true
        }
      ]
    }
  }
}

// GPT-4o Standard Backend (Primary - Spillover)
resource backendGpt4oStandardPrimary 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'aoai-gpt4o-standard-primary'
  properties: {
    title: 'Azure OpenAI GPT-4o Standard (Primary Region)'
    description: 'Standard deployment for GPT-4o spillover in primary region'
    url: '${aoaiPrimaryEndpoint}openai'
    protocol: 'http'
  }
}

// GPT-4o-mini PTU Backend (Primary)
resource backendGpt4oMiniPtuPrimary 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'aoai-gpt4o-mini-ptu-primary'
  properties: {
    title: 'Azure OpenAI GPT-4o-mini PTU (Primary Region)'
    description: 'PTU deployment for GPT-4o-mini in primary region'
    url: '${aoaiPrimaryEndpoint}openai'
    protocol: 'http'
    circuitBreaker: {
      rules: [
        {
          name: 'ptuThrottlingRule'
          failureCondition: {
            count: 3
            errorReasons: ['Timeout']
            interval: 'PT10S'
            statusCodeRanges: [
              { min: 429, max: 429 }
              { min: 500, max: 599 }
            ]
          }
          tripDuration: 'PT1M'
          acceptRetryAfter: true
        }
      ]
    }
  }
}

// GPT-4o-mini Standard Backend (Primary - Spillover)
resource backendGpt4oMiniStandardPrimary 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'aoai-gpt4o-mini-standard-primary'
  properties: {
    title: 'Azure OpenAI GPT-4o-mini Standard (Primary Region)'
    description: 'Standard deployment for GPT-4o-mini spillover in primary region'
    url: '${aoaiPrimaryEndpoint}openai'
    protocol: 'http'
  }
}

// ============================================================================
// Backends - Secondary Region (PTU + Standard)
// ============================================================================

// GPT-4o PTU Backend (Secondary)
resource backendGpt4oPtuSecondary 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'aoai-gpt4o-ptu-secondary'
  properties: {
    title: 'Azure OpenAI GPT-4o PTU (Secondary Region)'
    description: 'PTU deployment for GPT-4o in secondary region'
    url: '${aoaiSecondaryEndpoint}openai'
    protocol: 'http'
    circuitBreaker: {
      rules: [
        {
          name: 'ptuThrottlingRule'
          failureCondition: {
            count: 3
            errorReasons: ['Timeout']
            interval: 'PT10S'
            statusCodeRanges: [
              { min: 429, max: 429 }
              { min: 500, max: 599 }
            ]
          }
          tripDuration: 'PT1M'
          acceptRetryAfter: true
        }
      ]
    }
  }
}

// GPT-4o Standard Backend (Secondary - Spillover)
resource backendGpt4oStandardSecondary 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'aoai-gpt4o-standard-secondary'
  properties: {
    title: 'Azure OpenAI GPT-4o Standard (Secondary Region)'
    description: 'Standard deployment for GPT-4o spillover in secondary region'
    url: '${aoaiSecondaryEndpoint}openai'
    protocol: 'http'
  }
}

// GPT-4o-mini PTU Backend (Secondary)
resource backendGpt4oMiniPtuSecondary 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'aoai-gpt4o-mini-ptu-secondary'
  properties: {
    title: 'Azure OpenAI GPT-4o-mini PTU (Secondary Region)'
    description: 'PTU deployment for GPT-4o-mini in secondary region'
    url: '${aoaiSecondaryEndpoint}openai'
    protocol: 'http'
    circuitBreaker: {
      rules: [
        {
          name: 'ptuThrottlingRule'
          failureCondition: {
            count: 3
            errorReasons: ['Timeout']
            interval: 'PT10S'
            statusCodeRanges: [
              { min: 429, max: 429 }
              { min: 500, max: 599 }
            ]
          }
          tripDuration: 'PT1M'
          acceptRetryAfter: true
        }
      ]
    }
  }
}

// GPT-4o-mini Standard Backend (Secondary - Spillover)
resource backendGpt4oMiniStandardSecondary 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'aoai-gpt4o-mini-standard-secondary'
  properties: {
    title: 'Azure OpenAI GPT-4o-mini Standard (Secondary Region)'
    description: 'Standard deployment for GPT-4o-mini spillover in secondary region'
    url: '${aoaiSecondaryEndpoint}openai'
    protocol: 'http'
  }
}

// ============================================================================
// Backend Pools - Priority-based routing (PTU first, then Standard spillover)
// ============================================================================

// GPT-4o Backend Pool (Primary Region)
resource backendPoolGpt4oPrimary 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'pool-gpt4o-primary'
  dependsOn: [backendGpt4oPtuPrimary, backendGpt4oStandardPrimary]
  properties: {
    title: 'GPT-4o Backend Pool (Primary Region)'
    description: 'Load balances between PTU (priority) and Standard (spillover)'
    type: 'Pool'
    pool: {
      services: [
        {
          id: '/backends/${backendGpt4oPtuPrimary.name}'
          priority: 1
          weight: 1
        }
        {
          id: '/backends/${backendGpt4oStandardPrimary.name}'
          priority: 2
          weight: 1
        }
      ]
    }
  }
}

// GPT-4o-mini Backend Pool (Primary Region)
resource backendPoolGpt4oMiniPrimary 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'pool-gpt4o-mini-primary'
  dependsOn: [backendGpt4oMiniPtuPrimary, backendGpt4oMiniStandardPrimary]
  properties: {
    title: 'GPT-4o-mini Backend Pool (Primary Region)'
    description: 'Load balances between PTU (priority) and Standard (spillover)'
    type: 'Pool'
    pool: {
      services: [
        {
          id: '/backends/${backendGpt4oMiniPtuPrimary.name}'
          priority: 1
          weight: 1
        }
        {
          id: '/backends/${backendGpt4oMiniStandardPrimary.name}'
          priority: 2
          weight: 1
        }
      ]
    }
  }
}

// GPT-4o Backend Pool (Secondary Region)
resource backendPoolGpt4oSecondary 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'pool-gpt4o-secondary'
  dependsOn: [backendGpt4oPtuSecondary, backendGpt4oStandardSecondary]
  properties: {
    title: 'GPT-4o Backend Pool (Secondary Region)'
    description: 'Load balances between PTU (priority) and Standard (spillover)'
    type: 'Pool'
    pool: {
      services: [
        {
          id: '/backends/${backendGpt4oPtuSecondary.name}'
          priority: 1
          weight: 1
        }
        {
          id: '/backends/${backendGpt4oStandardSecondary.name}'
          priority: 2
          weight: 1
        }
      ]
    }
  }
}

// GPT-4o-mini Backend Pool (Secondary Region)
resource backendPoolGpt4oMiniSecondary 'Microsoft.ApiManagement/service/backends@2023-09-01-preview' = {
  parent: apim
  name: 'pool-gpt4o-mini-secondary'
  dependsOn: [backendGpt4oMiniPtuSecondary, backendGpt4oMiniStandardSecondary]
  properties: {
    title: 'GPT-4o-mini Backend Pool (Secondary Region)'
    description: 'Load balances between PTU (priority) and Standard (spillover)'
    type: 'Pool'
    pool: {
      services: [
        {
          id: '/backends/${backendGpt4oMiniPtuSecondary.name}'
          priority: 1
          weight: 1
        }
        {
          id: '/backends/${backendGpt4oMiniStandardSecondary.name}'
          priority: 2
          weight: 1
        }
      ]
    }
  }
}

// ============================================================================
// API Definition - Azure OpenAI
// ============================================================================

resource apiAoai 'Microsoft.ApiManagement/service/apis@2023-09-01-preview' = {
  parent: apim
  name: 'azure-openai-api'
  properties: {
    displayName: 'Azure OpenAI API'
    description: 'API for Azure OpenAI with PTU and PAYG spillover'
    serviceUrl: aoaiPrimaryEndpoint
    path: 'openai'
    protocols: ['https']
    subscriptionRequired: true
    subscriptionKeyParameterNames: {
      header: 'api-key'
      query: 'api-key'
    }
    apiType: 'http'
  }
}

// Chat Completions Operation - GPT-4o
resource operationChatGpt4o 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: apiAoai
  name: 'chat-completions-gpt4o'
  properties: {
    displayName: 'Chat Completions - GPT-4o'
    method: 'POST'
    urlTemplate: '/deployments/gpt-4o/chat/completions'
    description: 'Creates a chat completion for GPT-4o'
    request: {
      queryParameters: [
        {
          name: 'api-version'
          type: 'string'
          required: true
          defaultValue: '2024-08-01-preview'
        }
      ]
    }
  }
}

// Chat Completions Operation - GPT-4o-mini
resource operationChatGpt4oMini 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: apiAoai
  name: 'chat-completions-gpt4o-mini'
  properties: {
    displayName: 'Chat Completions - GPT-4o-mini'
    method: 'POST'
    urlTemplate: '/deployments/gpt-4o-mini/chat/completions'
    description: 'Creates a chat completion for GPT-4o-mini'
    request: {
      queryParameters: [
        {
          name: 'api-version'
          type: 'string'
          required: true
          defaultValue: '2024-08-01-preview'
        }
      ]
    }
  }
}

// Completions Operation - GPT-4o
resource operationCompletionsGpt4o 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: apiAoai
  name: 'completions-gpt4o'
  properties: {
    displayName: 'Completions - GPT-4o'
    method: 'POST'
    urlTemplate: '/deployments/gpt-4o/completions'
    description: 'Creates a completion for GPT-4o'
    request: {
      queryParameters: [
        {
          name: 'api-version'
          type: 'string'
          required: true
          defaultValue: '2024-08-01-preview'
        }
      ]
    }
  }
}

// Completions Operation - GPT-4o-mini
resource operationCompletionsGpt4oMini 'Microsoft.ApiManagement/service/apis/operations@2023-09-01-preview' = {
  parent: apiAoai
  name: 'completions-gpt4o-mini'
  properties: {
    displayName: 'Completions - GPT-4o-mini'
    method: 'POST'
    urlTemplate: '/deployments/gpt-4o-mini/completions'
    description: 'Creates a completion for GPT-4o-mini'
    request: {
      queryParameters: [
        {
          name: 'api-version'
          type: 'string'
          required: true
          defaultValue: '2024-08-01-preview'
        }
      ]
    }
  }
}

// ============================================================================
// API Policies
// ============================================================================

// Policy for GPT-4o operations - routes to backend pool
resource policyGpt4o 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: operationChatGpt4o
  name: 'policy'
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="pool-gpt4o-primary" />
    <authentication-managed-identity resource="https://cognitiveservices.azure.com" />
    <set-header name="Content-Type" exists-action="override">
      <value>application/json</value>
    </set-header>
    <rewrite-uri template="/deployments/gpt-4o-primary/chat/completions" />
  </inbound>
  <backend>
    <forward-request buffer-request-body="true" />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
}

resource policyGpt4oMini 'Microsoft.ApiManagement/service/apis/operations/policies@2023-09-01-preview' = {
  parent: operationChatGpt4oMini
  name: 'policy'
  properties: {
    format: 'xml'
    value: '''
<policies>
  <inbound>
    <base />
    <set-backend-service backend-id="pool-gpt4o-mini-primary" />
    <authentication-managed-identity resource="https://cognitiveservices.azure.com" />
    <set-header name="Content-Type" exists-action="override">
      <value>application/json</value>
    </set-header>
    <rewrite-uri template="/deployments/gpt-4o-mini-primary/chat/completions" />
  </inbound>
  <backend>
    <forward-request buffer-request-body="true" />
  </backend>
  <outbound>
    <base />
  </outbound>
  <on-error>
    <base />
  </on-error>
</policies>
'''
  }
}

// ============================================================================
// Products and Subscriptions
// ============================================================================

resource productAoai 'Microsoft.ApiManagement/service/products@2023-09-01-preview' = {
  parent: apim
  name: 'azure-openai-product'
  properties: {
    displayName: 'Azure OpenAI'
    description: 'Access to Azure OpenAI APIs with PTU and PAYG spillover'
    subscriptionRequired: true
    approvalRequired: false
    state: 'published'
  }
}

resource productApiLink 'Microsoft.ApiManagement/service/products/apis@2023-09-01-preview' = {
  parent: productAoai
  name: apiAoai.name
}

resource subscription 'Microsoft.ApiManagement/service/subscriptions@2023-09-01-preview' = {
  parent: apim
  name: 'aoai-subscription'
  properties: {
    displayName: 'Azure OpenAI Subscription'
    scope: '/products/${productAoai.id}'
    state: 'active'
    allowTracing: true
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource ID of the API Management service')
output id string = apim.id

@description('Name of the API Management service')
output name string = apim.name

@description('Gateway URL of the API Management service')
output gatewayUrl string = apim.properties.gatewayUrl

@description('Management API URL')
output managementApiUrl string = apim.properties.managementApiUrl

@description('Developer portal URL')
output developerPortalUrl string = apim.properties.developerPortalUrl

@description('Principal ID of the managed identity')
output principalId string = apim.identity.principalId
