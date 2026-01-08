# Deployment Guide - Azure Private Link Service

This guide explains how to deploy the Azure Private Link Service infrastructure with proper RBAC and security configurations.

## Prerequisites

- Azure CLI installed and authenticated
- Azure subscription with appropriate permissions
- Contributor role on the subscription or resource group

## Deployment Steps

### 1. Get Your Principal ID

First, retrieve your Azure AD user principal ID. This is required for Key Vault RBAC access:

```bash
# Get your user principal ID
PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)
echo "Your Principal ID: $PRINCIPAL_ID"
```

### 2. Set Deployment Variables

```bash
# Set your variables
RESOURCE_GROUP="rg-pls-demo"
LOCATION="eastus2"
ENV_NAME="plstest"
```

### 3. Create Resource Group

```bash
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION
```

### 4. Deploy Infrastructure

Deploy using the Bicep template with your principal ID:

```bash
az deployment group create \
  --resource-group $RESOURCE_GROUP \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters principalId="$PRINCIPAL_ID"
```

**Note**: The deployment automatically:
- Generates a secure random password for VMs
- Assigns you "Key Vault Secrets User" role on the Key Vault
- Applies SFI bypass tags to all resources
- Creates 3 VMs with 6 secrets in Key Vault

### 5. Verify Deployment

```bash
# Check deployment status
az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name main \
  --query "properties.provisioningState"

# Get Key Vault name
KV_NAME=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name main \
  --query "properties.outputs.keyVaultName.value" -o tsv)

echo "Key Vault: $KV_NAME"
```

### 6. Access VM Credentials

With the automatic RBAC assignment, you can now access secrets:

```bash
# Get client VM 1 credentials
CLIENT1_USERNAME=$(az keyvault secret show \
  --vault-name $KV_NAME \
  --name clientVm1-username \
  --query 'value' -o tsv)

CLIENT1_PASSWORD=$(az keyvault secret show \
  --vault-name $KV_NAME \
  --name clientVm1-password \
  --query 'value' -o tsv)

echo "Username: $CLIENT1_USERNAME"
echo "Password: $CLIENT1_PASSWORD"

# Get public IP
CLIENT_VM_IP=$(az deployment group show \
  --resource-group $RESOURCE_GROUP \
  --name main \
  --query "properties.outputs.clientVm1PublicIp.value" -o tsv)

echo "Public IP: $CLIENT_VM_IP"
```

### 7. Connect to VMs

```bash
# SSH to client VM
ssh $CLIENT1_USERNAME@$CLIENT_VM_IP
```

## PowerShell Deployment

For PowerShell users:

```powershell
# Get your principal ID
$PRINCIPAL_ID = (az ad signed-in-user show --query id -o tsv)
Write-Output "Your Principal ID: $PRINCIPAL_ID"

# Set variables
$RESOURCE_GROUP = "rg-pls-demo"
$LOCATION = "eastus2"

# Create resource group
az group create `
  --name $RESOURCE_GROUP `
  --location $LOCATION

# Deploy infrastructure
az deployment group create `
  --resource-group $RESOURCE_GROUP `
  --template-file main.bicep `
  --parameters main.bicepparam `
  --parameters principalId="$PRINCIPAL_ID"

# Get Key Vault name
$KV_NAME = (az deployment group show `
  --resource-group $RESOURCE_GROUP `
  --name main `
  --query "properties.outputs.keyVaultName.value" -o tsv)

Write-Output "Key Vault: $KV_NAME"

# Get credentials
$USERNAME = (az keyvault secret show `
  --vault-name $KV_NAME `
  --name clientVm1-username `
  --query 'value' -o tsv)

$PASSWORD = (az keyvault secret show `
  --vault-name $KV_NAME `
  --name clientVm1-password `
  --query 'value' -o tsv)

Write-Output "Username: $USERNAME"
Write-Output "Password: $PASSWORD"
```

## What Gets Deployed

### Resources Created:

1. **Key Vault** (with RBAC enabled)
   - 6 secrets (3 VMs × 2 credentials)
   - Automatic role assignment to deployment user
   
2. **Provider VNET** (172.16.0.0/16)
   - Private Link Service (4 NAT IPs)
   - Standard Load Balancer
   - Server VM (NGINX)
   - NAT Gateway
   - Server NSG

3. **Client VNET** (10.0.0.0/16)
   - 4 Private Endpoints
   - 2 Client VMs (with exhaust scripts)
   - Client NSG
   - 2 Public IPs (for VM management)

4. **Tags Applied** (all resources):
   - `azd-env-name`: plstest
   - `securityControl`: ignore

### Network Architecture:

```
Provider VNET (172.16.0.0/16)
│
├─ Server Subnet (172.16.1.0/24)
│  ├─ Private Link Service (4 NAT IPs)
│  ├─ Standard Load Balancer
│  └─ Server VM (NGINX)
│
Client VNET (10.0.0.0/16)
│
├─ PE Subnet (10.0.1.0/24)
│  ├─ Private Endpoint 1
│  ├─ Private Endpoint 2
│  ├─ Private Endpoint 3
│  └─ Private Endpoint 4
│
└─ VM Subnet (10.0.2.0/24)
   ├─ Client VM 1 (with public IP)
   └─ Client VM 2 (with public IP)
```

## Security Features

✅ **No Hardcoded Credentials**: Passwords auto-generated  
✅ **RBAC Enabled**: Key Vault uses Azure RBAC  
✅ **Automatic Access**: Deployment user gets Key Vault Secrets User role  
✅ **NSGs**: All VMs protected by Network Security Groups  
✅ **SFI Bypass Tags**: Compliance tags applied to all resources  
✅ **Public IPs**: Only on VMs for management access  

## Troubleshooting

### Issue: Cannot access Key Vault secrets

**Solution**: Verify your role assignment:

```bash
az role assignment list \
  --scope "/subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KV_NAME" \
  --assignee $PRINCIPAL_ID
```

### Issue: Deployment fails with principalId error

**Solution**: Ensure you pass the principalId parameter:

```bash
# Verify your principal ID is set
echo $PRINCIPAL_ID

# If empty, get it again
PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)
```

### Issue: Tags not showing on resources

**Solution**: Check deployment outputs:

```bash
az resource list \
  --resource-group $RESOURCE_GROUP \
  --query "[].{name:name, tags:tags}" \
  --output table
```

## Cleanup

```bash
# Delete all resources
az group delete \
  --name $RESOURCE_GROUP \
  --yes \
  --no-wait
```

## Next Steps

After deployment:
1. Follow the [Lab Instructions](../docs/instructions.md) for testing
2. Run SNAT exhaustion tests
3. Monitor metrics in Azure Portal

## Additional Resources

- [Azure Private Link Documentation](https://learn.microsoft.com/azure/private-link/)
- [Key Vault RBAC Guide](https://learn.microsoft.com/azure/key-vault/general/rbac-guide)
- [Azure Bicep Documentation](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)
