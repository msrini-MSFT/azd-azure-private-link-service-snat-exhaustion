param location string
param vaultName string
param tenantId string
param adminUsername string
@secure()
param serverVmPassword string
@secure()
param clientVm1Password string
@secure()
param clientVm2Password string
param principalId string = ''
param tags object = {}

resource kv 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: vaultName
  location: location
  tags: tags
  properties: {
    tenantId: tenantId
    sku: {
      family: 'A'
      name: 'standard'
    }
    enableRbacAuthorization: true
    enabledForTemplateDeployment: true
  }
}

// Key Vault Secrets User role definition
var keyVaultSecretsUserRoleId = '4633458b-17de-408a-b874-0445c86b69e6'

// Assign Key Vault Secrets User role to deployment user
resource keyVaultRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-10-01-preview' = if (principalId != '') {
  name: guid(kv.id, principalId, keyVaultSecretsUserRoleId)
  scope: kv
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', keyVaultSecretsUserRoleId)
    principalId: principalId
    principalType: 'User'
  }
}

// Client VM 1 credentials
resource clientVm1UsernameSecret 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: kv
  name: 'clientVm1-username'
  properties: {
    value: adminUsername
  }
}

resource clientVm1PasswordSecret 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: kv
  name: 'clientVm1-password'
  properties: {
    value: clientVm1Password
  }
}

resource clientVm2UsernameSecret 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: kv
  name: 'clientVm2-username'
  properties: {
    value: adminUsername
  }
}

resource clientVm2PasswordSecret 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: kv
  name: 'clientVm2-password'
  properties: {
    value: clientVm2Password
  }
}

resource serverVmUsernameSecret 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: kv
  name: 'serverVm-username'
  properties: {
    value: adminUsername
  }
}

resource serverVmPasswordSecret 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: kv
  name: 'serverVm-password'
  properties: {
    value: serverVmPassword
  }
}

output keyVaultName string = kv.name
