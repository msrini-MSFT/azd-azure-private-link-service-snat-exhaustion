using './main.bicep'

param environmentName = 'plstest'
param adminUsername = 'azureuser'
// Generate secure password at deployment time using: az deployment group create ... --parameters adminPassword="$(openssl rand -base64 32)"
param location = 'eastus2'
