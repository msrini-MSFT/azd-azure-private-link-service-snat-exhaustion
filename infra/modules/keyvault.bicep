param location string
param vaultName string
param tenantId string
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

resource secret 'Microsoft.KeyVault/vaults/secrets@2021-06-01-preview' = {
  parent: kv
  name: 'vmAdminPassword'
  properties: {
    value: adminPassword
  }
}

output keyVaultName string = kv.name
