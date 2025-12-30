# Lab: Testing Azure Private Link Service SNAT Port Exhaustion

## Lab Overview

In this lab, you will deploy and test Azure Private Link Service (PLS) to understand SNAT port exhaustion behavior and NAT IP scaling.

**Duration**: 60-90 minutes

## Learning Objectives

By the end of this lab, you will be able to:
- Deploy Azure Private Link Service infrastructure
- Configure Private Endpoints to access PLS
- Test connectivity through Private Link
- Simulate and monitor SNAT port exhaustion
- Understand NAT IP scaling strategies

## Architecture

You will deploy two virtual networks:

- **Client VNET**: Contains client VMs and Private Endpoints
- **Provider VNET**: Contains PLS, Load Balancer, and server VM

There is no direct connectivity between these VNETs—all communication flows through Private Link Service.

## Prerequisites

- Active Azure subscription
- Azure CLI installed and configured
- SSH client (built-in on Linux/Mac, or use PuTTY on Windows)
- Basic understanding of:
  - Azure Virtual Networks
  - Azure Load Balancer
  - Linux command line

---

## Exercise 1: Deploy the Infrastructure

### Task 1: Clone the Repository

1. Open a terminal or command prompt

2. Clone the repository:
   ```bash
   git clone https://github.com/msrini-MSFT/azd-azure-private-link-service-snat-exhaustion.git
   cd azd-azure-private-link-service-snat-exhaustion
   ```

### Task 2: Create Resource Group

1. Log in to Azure CLI:
   ```bash
   az login
   ```

2. Set your subscription (if you have multiple):
   ```bash
   az account set --subscription "<your-subscription-id>"
   ```

3. Create the resource group:
   ```bash
   az group create \
     --name rg-pls-lab \
     --location eastus2
   ```

### Task 3: Deploy Bicep Template

1. Generate a secure password:
   ```bash
   # On Linux/Mac
   SECURE_PASSWORD=$(openssl rand -base64 32)
   
   # On Windows PowerShell
   $SECURE_PASSWORD = -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 32 | % {[char]$_})
   ```

2. Navigate to the infrastructure directory:
   ```bash
   cd infra
   ```

3. Deploy the Bicep template:
   ```bash
   az deployment group create \
     --resource-group rg-pls-lab \
     --template-file main.bicep \
     --parameters main.bicepparam \
     --parameters adminPassword="$SECURE_PASSWORD"
   ```

   > **Note**: Deployment takes approximately 10-15 minutes.

4. Verify deployment completed successfully:
   ```bash
   az deployment group show \
     --resource-group rg-pls-lab \
     --name main \
     --query "properties.provisioningState"
   ```

   Expected output: `"Succeeded"`

---

## Exercise 2: Access Client Virtual Machines

### Task 1: Configure Key Vault Access

1. Navigate to Azure Portal: https://portal.azure.com

2. Search for **Key Vaults** and select the vault created by the deployment (starts with `kv-`)

3. In the left menu, select **Access control (IAM)**

4. Click **+ Add** → **Add role assignment**

5. Select **Key Vault Secrets User** role → **Next**

6. Click **+ Select members** → find your account → **Select** → **Review + assign**

### Task 2: Retrieve VM Credentials

Using Azure CLI:

```bash
# Get Key Vault name
KV_NAME=$(az deployment group show \
  --resource-group rg-pls-lab \
  --name main \
  --query "properties.outputs.keyVaultName.value" -o tsv)

echo "Key Vault: $KV_NAME"

# Retrieve credentials
USERNAME=$(az keyvault secret show \
  --vault-name $KV_NAME \
  --name clientVm1-username \
  --query 'value' -o tsv)

PASSWORD=$(az keyvault secret show \
  --vault-name $KV_NAME \
  --name clientVm1-password \
  --query 'value' -o tsv)

echo "Username: $USERNAME"
echo "Password: $PASSWORD"
```

> **Important**: Save these credentials—you'll need them throughout the lab.

### Task 3: Get Client VM Public IP

```bash
CLIENT_VM_IP=$(az vm show \
  --resource-group rg-pls-lab \
  --name plstest-client-vm-1 \
  --show-details \
  --query "publicIps" -o tsv)

echo "Client VM IP: $CLIENT_VM_IP"
```

---

## Exercise 3: Test Private Link Connectivity

### Task 1: Connect to Client VM

1. SSH to the client VM:
   ```bash
   ssh $USERNAME@$CLIENT_VM_IP
   ```

2. When prompted, enter the password retrieved from Key Vault

### Task 2: Verify NGINX Backend

Before testing through Private Link, verify the backend server is running:

```bash
# The Private Endpoint IPs are typically in the 10.0.1.x range
# Check the subnet configuration to identify exact IPs
curl http://10.0.1.4
```

**Expected Output**: NGINX default welcome page HTML content.

If you receive a response, this confirms:
✅ Private Endpoint is functioning  
✅ Private Link Service is routing traffic  
✅ Load Balancer is forwarding to backend  
✅ NGINX is responding  

### Task 3: Test Multiple Private Endpoints

The deployment creates 4 Private Endpoints. Test each one:

```bash
# Test PE1
curl http://10.0.1.4

# Test PE2
curl http://10.0.1.5

# Test PE3
curl http://10.0.1.6

# Test PE4
curl http://10.0.1.7
```

> **Note**: Adjust IP addresses based on your actual Private Endpoint IPs. You can find these in the Azure Portal under the Private Endpoint resources.

---

## Exercise 4: Understand SNAT Port Exhaustion

### Task 1: Review SNAT Concepts

**What is SNAT?**
- Source Network Address Translation
- PLS performs SNAT on client connections
- Each NAT IP supports **64,000 concurrent flows**

**Why does exhaustion occur?**
- Multiple clients connecting through Private Endpoints
- High volume of concurrent connections
- Limited NAT IP capacity

**How to scale?**
- Configure up to 8 NAT IPs per PLS
- Total capacity: 8 × 64,000 = **512,000 flows**

### Task 2: Check Current NAT IP Configuration

1. In Azure Portal, navigate to your Private Link Service resource

2. Select **Overview** → note the number of NAT IPs configured (default: 4)

3. Click **Properties** → review NAT IP addresses

---

## Exercise 5: Simulate SNAT Port Exhaustion

### Task 1: Examine the Exhaustion Script

While connected to the client VM:

```bash
# View the script
cat /home/azureuser/exhaust_snat.py

# Check if Python 3 is available
python3 --version
```

The script uses socket programming to create and maintain persistent TCP connections.

### Task 2: Run Small-Scale Test

Start with a smaller number of connections to verify functionality:

```bash
# Test with 1,000 connections
python3 /home/azureuser/exhaust_snat.py 10.0.1.4 80 1000
```

In another terminal (SSH session), monitor active connections:

```bash
# Count established connections
ss -tn dst 10.0.1.4 | grep ESTAB | wc -l
```

### Task 3: Scale Up to Trigger Exhaustion

Now run with a larger connection count to approach SNAT limits:

```bash
# Run in background with 60,000 connections
nohup python3 /home/azureuser/exhaust_snat.py 10.0.1.4 80 60000 > /tmp/exhaust.log 2>&1 &

# Get process ID
ps aux | grep exhaust_snat.py | grep -v grep

# Monitor log output
tail -f /tmp/exhaust.log
```

### Task 4: Run on Multiple Client VMs

To fully exhaust SNAT ports, run the script on both client VMs:

1. SSH to Client VM 2:
   ```bash
   # Get credentials for VM2 from Key Vault
   USERNAME2=$(az keyvault secret show \
     --vault-name $KV_NAME \
     --name clientVm2-username \
     --query 'value' -o tsv)
   
   PASSWORD2=$(az keyvault secret show \
     --vault-name $KV_NAME \
     --name clientVm2-password \
     --query 'value' -o tsv)
   
   # Get public IP
   CLIENT_VM2_IP=$(az vm show \
     --resource-group rg-pls-lab \
     --name plstest-client-vm-2 \
     --show-details \
     --query "publicIps" -o tsv)
   
   # Connect
   ssh $USERNAME2@$CLIENT_VM2_IP
   ```

2. Run the exhaustion script on VM2:
   ```bash
   nohup python3 /home/azureuser/exhaust_snat.py 10.0.1.5 80 60000 > /tmp/exhaust.log 2>&1 &
   ```

---

## Exercise 6: Monitor SNAT Port Usage

### Task 1: View Metrics in Azure Portal

1. Navigate to Azure Portal

2. Open your **Private Link Service** resource

3. In the left menu, select **Monitoring** → **Metrics**

4. Configure the metric:
   - Metric: **NAT port usage**
   - Aggregation: **Max** or **Average**
   - Time range: **Last 30 minutes**

5. Click **Add filter** or **Apply splitting**:
   - Property: **Nat IP**
   - Values: Select all NAT IPs

6. Observe the chart showing usage per NAT IP address

### Task 2: Analyze the Data

Look for these patterns:
- **Even distribution**: Connections spread across all NAT IPs
- **Approaching limits**: Usage nearing 64,000 per NAT IP
- **Exhaustion**: Flat-lining at 64K with connection failures

### Task 3: Test Connection Failures (Optional)

If SNAT exhaustion is reached:

1. From a third client, attempt to connect:
   ```bash
   curl http://10.0.1.4 --connect-timeout 5
   ```

2. **Expected behavior**: Connection timeout or failure

3. **Why?**: All available SNAT ports are consumed

---

## Exercise 7: Observe NAT IP Failover

### Task 1: Monitor Active NAT IPs

While the exhaustion test is running:

1. In the metrics view, watch which NAT IPs are being used

2. Note the order in which NAT IPs are consumed:
   - First NAT IP fills to ~64K
   - Second NAT IP starts accepting connections
   - Pattern continues until all NAT IPs are used

### Task 2: Check Backend Server

Verify the backend server perspective:

```bash
# Get server VM credentials
SERVER_USERNAME=$(az keyvault secret show \
  --vault-name $KV_NAME \
  --name serverVm-username \
  --query 'value' -o tsv)

SERVER_PASSWORD=$(az keyvault secret show \
  --vault-name $KV_NAME \
  --name serverVm-password \
  --query 'value' -o tsv)

SERVER_IP=$(az vm show \
  --resource-group rg-pls-lab \
  --name plstest-server-vm \
  --show-details \
  --query "publicIps" -o tsv)

# Connect
ssh $SERVER_USERNAME@$SERVER_IP

# View active connections (you'll see NAT IPs as sources)
ss -tn state established | grep :80 | awk '{print $4}' | cut -d: -f1 | sort | uniq -c | sort -rn
```

You'll see connections coming from the NAT IP addresses, not the client VMs' actual IPs.

---

## Exercise 8: Clean Up Resources

### Task 1: Stop Exhaustion Scripts

On each client VM:

```bash
# Find the process
ps aux | grep exhaust_snat.py | grep -v grep

# Kill the process (replace <PID> with actual process ID)
kill <PID>

# Or kill all Python processes
pkill -9 python3
```

### Task 2: Delete Azure Resources

```bash
# Delete the resource group (this removes all resources)
az group delete \
  --name rg-pls-lab \
  --yes \
  --no-wait
```

> **Note**: Resource deletion takes 5-10 minutes.

### Task 3: Verify Cleanup

```bash
# Check if resource group still exists
az group show --name rg-pls-lab
```

Expected: `ResourceGroupNotFound` error.

---

## Review Questions

1. **What is the maximum number of concurrent flows per NAT IP in Private Link Service?**
   <details>
   <summary>Answer</summary>
   64,000 concurrent flows per NAT IP address.
   </details>

2. **How many NAT IPs can be configured for a single Private Link Service?**
   <details>
   <summary>Answer</summary>
   Up to 8 NAT IP addresses.
   </details>

3. **What happens when SNAT port exhaustion occurs?**
   <details>
   <summary>Answer</summary>
   New connection attempts time out or fail because no available SNAT ports remain.
   </details>

4. **What is the difference between Private Link Service and Private Endpoint?**
   <details>
   <summary>Answer</summary>
   
   - **Private Link Service (PLS)**: Used to privately publish your own services for others to consume
   - **Private Endpoint**: Used to privately connect to Azure PaaS services (like Storage, SQL Database)
   </details>

5. **How can you monitor SNAT port usage?**
   <details>
   <summary>Answer</summary>
   Use Azure Monitor Metrics on the Private Link Service resource, selecting the "NAT port usage" metric with splitting by NAT IP.
   </details>

---

## Additional Resources

- [Azure Private Link Service Overview](https://learn.microsoft.com/azure/private-link/private-link-service-overview)
- [Private Link Service NAT IP Configuration](https://learn.microsoft.com/azure/private-link/private-link-service-overview#nat-ip-configuration)
- [Azure Load Balancer Documentation](https://learn.microsoft.com/azure/load-balancer/)
- [Azure Monitor Metrics](https://learn.microsoft.com/azure/azure-monitor/essentials/metrics-supported#microsoftnetworkprivatelinkservices)

---

## Troubleshooting

### Issue: Cannot SSH to Client VM

**Possible Causes**:
- NSG blocking port 22
- Incorrect credentials
- VM not fully provisioned

**Solutions**:
1. Check NSG rules in Azure Portal
2. Verify credentials from Key Vault
3. Ensure VM status is "Running"

### Issue: curl Returns "Connection Refused"

**Possible Causes**:
- NGINX not running on backend VM
- Load Balancer health probe failing
- Private Endpoint misconfigured

**Solutions**:
1. Check NGINX status: `sudo systemctl status nginx`
2. Verify Load Balancer backend health in Portal
3. Review Private Endpoint status

### Issue: SNAT Exhaustion Not Occurring

**Possible Causes**:
- Not enough concurrent connections
- Too many NAT IPs configured
- Connections closing too quickly

**Solutions**:
1. Increase connection count in script (try 100,000+)
2. Run script on multiple VMs simultaneously
3. Verify script is maintaining connections (not closing immediately)

### Issue: Key Vault Access Denied

**Possible Causes**:
- Missing role assignment
- Wrong subscription context
- Not signed in to Azure CLI

**Solutions**:
1. Assign "Key Vault Secrets User" role in Azure Portal
2. Verify subscription: `az account show`
3. Re-authenticate: `az login`

---

## Lab Summary

Congratulations! You have successfully:
✅ Deployed Azure Private Link Service infrastructure  
✅ Connected to VMs using Private Endpoints  
✅ Simulated SNAT port exhaustion  
✅ Monitored NAT IP usage patterns  
✅ Understood PLS scaling strategies  

You now have hands-on experience with Azure Private Link Service and understand how to design for SNAT port capacity planning.
