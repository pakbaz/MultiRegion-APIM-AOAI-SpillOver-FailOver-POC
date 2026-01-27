// ============================================================================
// Cognitive Services User Role Assignment Module
// Assigns Cognitive Services User role to a principal for Azure OpenAI access
// ============================================================================

@description('Principal ID to assign the role to')
param principalId string

@description('Name of the Cognitive Services account')
param cognitiveServicesAccountName string

@description('Role definition ID for Cognitive Services User')
var cognitiveServicesUserRoleId = 'a97b65f3-24c7-4388-baec-2e87135dc908'

// Reference existing Cognitive Services account
resource cognitiveServicesAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: cognitiveServicesAccountName
}

// Role assignment
resource roleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cognitiveServicesAccount.id, principalId, cognitiveServicesUserRoleId)
  scope: cognitiveServicesAccount
  properties: {
    principalId: principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesUserRoleId)
    principalType: 'ServicePrincipal'
  }
}

@description('Role assignment ID')
output roleAssignmentId string = roleAssignment.id
