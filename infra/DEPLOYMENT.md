# Secure Deployment Guide

## Security Best Practices Implemented

1. **No hardcoded passwords**: Passwords are generated at deployment time using `newGuid()`
2. **Key Vault storage**: All credentials are stored in Azure Key Vault after deployment
3. **NSG on all VMs**: Both client and server VMs have Network Security Groups attached
4. **SSH access**: Port 22 is allowed through NSGs for administrative access

## Deployment Instructions

### Option 1: Auto-generate password (Recommended)

```bash
# Deploy with auto-generated secure password
az deployment group create \
  --resource-group rg-pls-bicep-test \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --name main-secure

# Retrieve the generated password from Key Vault
KV_NAME=$(az deployment group show \
  --resource-group rg-pls-bicep-test \
  --name main-secure \
  --query "properties.outputs.keyVaultName.value" -o tsv)

# Get credentials (requires Key Vault access)
az keyvault secret show --vault-name $KV_NAME --name vmAdminUsername --query "value" -o tsv
az keyvault secret show --vault-name $KV_NAME --name vmAdminPassword --query "value" -o tsv
```

### Option 2: Provide your own secure password

```bash
# Generate a secure password
SECURE_PASS=$(openssl rand -base64 32)

# Deploy with your password
az deployment group create \
  --resource-group rg-pls-bicep-test \
  --template-file main.bicep \
  --parameters main.bicepparam \
  --parameters adminPassword="$SECURE_PASS" \
  --name main-secure

# Save the password securely (e.g., in a password manager)
echo "Password: $SECURE_PASS"
```

### Retrieve Credentials After Deployment

```bash
# Get Key Vault name
KV_NAME=$(az deployment group show \
  --resource-group rg-pls-bicep-test \
  --name main-secure \
  --query "properties.outputs.keyVaultName.value" -o tsv)

# Get all VM credentials
echo "Username: $(az keyvault secret show --vault-name $KV_NAME --name vmAdminUsername --query 'value' -o tsv)"
echo "Password: $(az keyvault secret show --vault-name $KV_NAME --name vmAdminPassword --query 'value' -o tsv)"

# Get public IPs
az deployment group show \
  --resource-group rg-pls-bicep-test \
  --name main-secure \
  --query "properties.outputs.{clientVm1:clientVm1PublicIp.value, clientVm2:clientVm2PublicIp.value, serverVm:serverVmPublicIp.value}" \
  -o table
```

## SSH Access

```bash
# Get credentials and IPs
USERNAME=$(az keyvault secret show --vault-name $KV_NAME --name vmAdminUsername --query 'value' -o tsv)
SERVER_IP=$(az deployment group show --resource-group rg-pls-bicep-test --name main-secure --query "properties.outputs.serverVmPublicIp.value" -o tsv)

# SSH to server VM
ssh $USERNAME@$SERVER_IP
```

## NSG Configuration

Both client and server VMs have NSGs that allow:
- **SSH (port 22)**: From any source (0.0.0.0/0)
- Priority: 1000

For production environments, consider restricting SSH access to specific IP ranges.
