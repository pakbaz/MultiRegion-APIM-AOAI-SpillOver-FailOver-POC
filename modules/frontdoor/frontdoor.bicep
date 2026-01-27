// ============================================================================
// Azure Front Door Module
// Deploys Azure Front Door Premium with APIM backends and health probes
// ============================================================================

@description('Name of the Azure Front Door profile')
param name string

@description('Tags to apply to the resource')
param tags object = {}

@description('Primary APIM gateway URL')
param apimPrimaryGatewayUrl string

@description('Secondary APIM gateway URL')
param apimSecondaryGatewayUrl string

@description('Primary region name for labeling')
param primaryRegionName string = 'eastus'

@description('Secondary region name for labeling')
param secondaryRegionName string = 'westus'

// ============================================================================
// Azure Front Door Profile (Premium)
// ============================================================================

resource frontDoor 'Microsoft.Cdn/profiles@2024-02-01' = {
  name: name
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    originResponseTimeoutSeconds: 60
  }
}

// ============================================================================
// Origin Group - APIM Backends
// Active-Active with health probes
// ============================================================================

resource originGroup 'Microsoft.Cdn/profiles/originGroups@2024-02-01' = {
  parent: frontDoor
  name: 'apim-origin-group'
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
      additionalLatencyInMilliseconds: 50
    }
    healthProbeSettings: {
      probePath: '/status-0123456789abcdef'
      probeRequestType: 'GET'
      probeProtocol: 'Https'
      probeIntervalInSeconds: 30
    }
    sessionAffinityState: 'Disabled'
  }
}

// ============================================================================
// Origins - APIM Instances
// ============================================================================

// Primary Region APIM Origin
resource originPrimary 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: originGroup
  name: 'apim-${primaryRegionName}'
  properties: {
    hostName: replace(replace(apimPrimaryGatewayUrl, 'https://', ''), '/', '')
    httpPort: 80
    httpsPort: 443
    originHostHeader: replace(replace(apimPrimaryGatewayUrl, 'https://', ''), '/', '')
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

// Secondary Region APIM Origin
resource originSecondary 'Microsoft.Cdn/profiles/originGroups/origins@2024-02-01' = {
  parent: originGroup
  name: 'apim-${secondaryRegionName}'
  properties: {
    hostName: replace(replace(apimSecondaryGatewayUrl, 'https://', ''), '/', '')
    httpPort: 80
    httpsPort: 443
    originHostHeader: replace(replace(apimSecondaryGatewayUrl, 'https://', ''), '/', '')
    priority: 1
    weight: 1000
    enabledState: 'Enabled'
    enforceCertificateNameCheck: true
  }
}

// ============================================================================
// Endpoint
// ============================================================================

resource endpoint 'Microsoft.Cdn/profiles/afdEndpoints@2024-02-01' = {
  parent: frontDoor
  name: '${name}-endpoint'
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

// ============================================================================
// Routes
// ============================================================================

// Route for OpenAI API
resource routeOpenAI 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: endpoint
  name: 'openai-route'
  dependsOn: [originPrimary, originSecondary]
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: ['Https']
    patternsToMatch: ['/openai/*']
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
    cacheConfiguration: {
      queryStringCachingBehavior: 'IgnoreQueryString'
      compressionSettings: {
        isCompressionEnabled: false
      }
    }
  }
}

// Default route
resource routeDefault 'Microsoft.Cdn/profiles/afdEndpoints/routes@2024-02-01' = {
  parent: endpoint
  name: 'default-route'
  dependsOn: [originPrimary, originSecondary, routeOpenAI]
  properties: {
    originGroup: {
      id: originGroup.id
    }
    supportedProtocols: ['Https']
    patternsToMatch: ['/*']
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    enabledState: 'Enabled'
  }
}

// ============================================================================
// WAF Policy (Optional but recommended)
// ============================================================================

resource wafPolicy 'Microsoft.Network/FrontDoorWebApplicationFirewallPolicies@2024-02-01' = {
  name: '${replace(name, '-', '')}waf'
  location: 'global'
  tags: tags
  sku: {
    name: 'Premium_AzureFrontDoor'
  }
  properties: {
    policySettings: {
      mode: 'Detection'
      requestBodyCheck: 'Enabled'
      customBlockResponseStatusCode: 403
    }
    managedRules: {
      managedRuleSets: [
        {
          ruleSetType: 'Microsoft_DefaultRuleSet'
          ruleSetVersion: '2.1'
          ruleSetAction: 'Block'
        }
        {
          ruleSetType: 'Microsoft_BotManagerRuleSet'
          ruleSetVersion: '1.0'
          ruleSetAction: 'Block'
        }
      ]
    }
  }
}

// Link WAF Policy to Endpoint
resource securityPolicy 'Microsoft.Cdn/profiles/securityPolicies@2024-02-01' = {
  parent: frontDoor
  name: 'waf-security-policy'
  properties: {
    parameters: {
      type: 'WebApplicationFirewall'
      wafPolicy: {
        id: wafPolicy.id
      }
      associations: [
        {
          domains: [
            {
              id: endpoint.id
            }
          ]
          patternsToMatch: ['/*']
        }
      ]
    }
  }
}

// ============================================================================
// Outputs
// ============================================================================

@description('Resource ID of the Front Door profile')
output id string = frontDoor.id

@description('Name of the Front Door profile')
output name string = frontDoor.name

@description('Front Door endpoint hostname')
output endpointHostName string = endpoint.properties.hostName

@description('Front Door endpoint URL')
output endpointUrl string = 'https://${endpoint.properties.hostName}'

@description('Origin group ID')
output originGroupId string = originGroup.id
