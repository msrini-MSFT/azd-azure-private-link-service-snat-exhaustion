param location string
param vaultName string
param tenantId string
param adminUsername string
@secure()
param adminPassword string

resource kv 'Microsoft.KeyVault/vaults@2021-06-01-preview' = {
  name: vaultName
  location: location
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
    value: adminPassword
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
    value: adminPassword
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
    value: adminPassword
  }
}

output keyVaultName string = kv.name
