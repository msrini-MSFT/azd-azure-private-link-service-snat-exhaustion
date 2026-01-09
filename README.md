# Azure Private Link Service - SNAT Port Exhaustion Test

This Terraform configuration deploys an Azure infrastructure to test SNAT port exhaustion on Private Link Service.

## Architecture

- **PLS Side:**
  - Virtual Network (10.0.0.0/16)
  - Standard Load Balancer with private frontend
  - Backend VM running nginx web server
  - Private Link Service connected to the load balancer

- **PE Side:**
  - Virtual Network (10.1.0.0/16)
  - Private Endpoint connected to the Private Link Service
  - Client VM with port exhaustion script

## Prerequisites

1. Azure CLI installed and authenticated
2. Terraform installed (use: `winget install Hashicorp.Terraform`)
3. SSH key pair for VM access

## Setup

1. Generate SSH key pair (if you don't have one):
   ```bash
   ssh-keygen -t rsa -b 4096 -f ~/.ssh/azure_pls_test
   ```

2. Get your Azure subscription ID:
   ```bash
   az account show --query id -o tsv
   ```

3. Create `terraform.tfvars` file:
   ```hcl
   subscription_id = "YOUR_SUBSCRIPTION_ID"
   ssh_public_key  = "YOUR_SSH_PUBLIC_KEY_CONTENT"
   ```

## Deployment

1. Initialize Terraform:
   ```bash
   terraform init
   ```

2. Validate configuration:
   ```bash
   terraform validate
   ```

3. Review deployment plan:
   ```bash
   terraform plan
   ```

4. Deploy infrastructure:
   ```bash
   terraform apply -auto-approve
   ```

## Testing SNAT Port Exhaustion

### Using the Enhanced Multi-PE Script (Recommended)

The deployment includes a pre-loaded Python script that creates connections across all 4 Private Endpoints simultaneously.

1. After deployment, note the client VM public IP from outputs

2. SSH to the client VM:
   ```bash
   ssh azureuser@<CLIENT_VM_PUBLIC_IP>
   ```

3. Run the multi-PE SNAT exhaustion script:
   ```bash
   # Default: 16K connections per PE = 64K total (50% SNAT usage with 2 NAT IPs)
   python3 ~/exhaust_snat_multi_pe.py
   
   # Custom connection count per PE:
   python3 ~/exhaust_snat_multi_pe.py 20000  # 80K total connections
   
   # Run in background:
   nohup python3 ~/exhaust_snat_multi_pe.py 16000 > ~/snat_test.log 2>&1 &
   ```

### Script Features
- ✅ **Distributes load across all 4 Private Endpoints** (10.0.1.4-7)
- ✅ **Sequential round-robin strategy** - stable, no crashes
- ✅ **Real-time progress tracking** per PE
- ✅ **Automatic SNAT calculations** for 1 or 2 NAT IPs
- ✅ **Graceful shutdown** with Ctrl+C

### Monitoring in Azure Portal

1. Navigate to the Private Link Service resource
2. Go to **Metrics** blade
3. Select metrics:
   - **SNAT Connection Count**: Active SNAT connections
   - **Allocated SNAT Ports**: Total available ports
   - **Used SNAT Ports**: Ports currently in use
   - **Bytes Processed**: Data throughput
4. Observe real-time SNAT exhaustion as connections increase

### Multi-VM Testing for Higher Exhaustion

To achieve 100% SNAT exhaustion (128K connections with 2 NAT IPs):

```bash
# On Client VM 1:
ssh azureuser@<CLIENT_VM_1_IP>
python3 ~/exhaust_snat_multi_pe.py 16000  # 64K connections

# On Client VM 2 (simultaneously):
ssh azureuser@<CLIENT_VM_2_IP>
python3 ~/exhaust_snat_multi_pe.py 16000  # 64K connections

# Combined: 128K connections = 100% SNAT usage
```

📖 **Detailed Documentation**: See [MULTI_PE_SNAT_TEST.md](./MULTI_PE_SNAT_TEST.md) for comprehensive usage guide, troubleshooting, and scenarios.

## Cleanup

To remove all resources:
```bash
terraform destroy -auto-approve
```

## Resources Created

- Resource Group
- 2 Virtual Networks (PLS and PE sides)
- 4 Subnets
- Standard Load Balancer
- Private Link Service
- Private Endpoint
- 2 Linux VMs (backend and client)
- Network Security Groups
- Network Interfaces
- Public IPs

## Metrics to Monitor

In the Azure Portal, monitor these Private Link Service metrics:
- **SNAT Connection Count**: Number of active SNAT connections
- **Allocated SNAT Ports**: Number of SNAT ports allocated
- **Used SNAT Ports**: Number of SNAT ports currently in use
- **Bytes Processed**: Data throughput
