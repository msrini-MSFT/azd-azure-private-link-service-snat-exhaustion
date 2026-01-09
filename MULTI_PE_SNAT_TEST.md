# Multi-PE SNAT Exhaustion Testing Guide

## Overview
The `exhaust_snat_multi_pe.py` script creates persistent connections distributed across all 4 Private Endpoints to maximize SNAT port usage on the Azure Private Link Service.

## Private Endpoint Configuration
- **PE1**: 10.0.1.4 (plstest-client-pe-1)
- **PE2**: 10.0.1.5 (plstest-client-pe-2)
- **PE3**: 10.0.1.6 (plstest-client-pe-3)
- **PE4**: 10.0.1.7 (plstest-client-pe-4)

## Script Location
- **GitHub**: https://raw.githubusercontent.com/msrini-MSFT/azd-azure-private-link-service-snat-exhaustion/main/exhaust_snat_multi_pe.py
- **Local**: `c:\Users\msrini\OneDrive - Microsoft\Documents\Azure-Deploy-PLS\exhaust_snat_multi_pe.py`

## Usage

### Download to VM
```bash
curl -s https://raw.githubusercontent.com/msrini-MSFT/azd-azure-private-link-service-snat-exhaustion/main/exhaust_snat_multi_pe.py -o ~/exhaust_snat_multi_pe.py
chmod +x ~/exhaust_snat_multi_pe.py
```

### Run the Script

#### Default (15K connections per PE = 60K total)
```bash
python3 ~/exhaust_snat_multi_pe.py
```

#### Custom connection count per PE
```bash
# 10K per PE = 40K total
python3 ~/exhaust_snat_multi_pe.py 10000

# 5K per PE = 20K total
python3 ~/exhaust_snat_multi_pe.py 5000
```

#### Run in background
```bash
nohup python3 ~/exhaust_snat_multi_pe.py 15000 > ~/snat_test.log 2>&1 &
```

### Monitor Progress

#### Check running processes
```bash
ps aux | grep exhaust_snat_multi_pe | grep -v grep
```

#### View real-time log
```bash
tail -f ~/snat_test.log
```

#### Check active connections
```bash
# Connections to all PEs
ss -tn | grep -E "10.0.1.[4-7]:80" | wc -l

# Connections per PE
echo "PE1 (10.0.1.4): $(ss -tn | grep 10.0.1.4:80 | wc -l)"
echo "PE2 (10.0.1.5): $(ss -tn | grep 10.0.1.5:80 | wc -l)"
echo "PE3 (10.0.1.6): $(ss -tn | grep 10.0.1.6:80 | wc -l)"
echo "PE4 (10.0.1.7): $(ss -tn | grep 10.0.1.7:80 | wc -l)"
```

### Stop the Test
```bash
# Find and kill the process
pkill -f exhaust_snat_multi_pe.py

# Or use Ctrl+C if running in foreground
```

## Expected Output

```
==============================================================
Target: 15000 connections per PE x 4 PEs
Total target: 60000 connections
==============================================================
Current limits: soft=1024, hard=1048576
New limits: (1048576, 1048576)
[PE1] Connecting to 10.0.1.4:80 (target: 15000)
[PE2] Connecting to 10.0.1.5:80 (target: 15000)
[PE3] Connecting to 10.0.1.6:80 (target: 15000)
[PE4] Connecting to 10.0.1.7:80 (target: 15000)
[PE1] 1000/15000 connections
[PE2] 1000/15000 connections
[PE3] 1000/15000 connections
[PE4] 1000/15000 connections
...
[PE1] Done: Holding 15000 connections
[PE2] Done: Holding 14998 connections
[PE3] Done: Holding 15000 connections
[PE4] Done: Holding 14999 connections

==============================================================
Total connections: 59997
Time: 45.3s (1325 conn/s)
SNAT usage: 1 NAT IP (64K) = 93.7%
SNAT usage: 2 NAT IPs (128K) = 46.9%
==============================================================
Holding connections... Press Ctrl+C to stop
```

## Azure Portal Monitoring

### View PLS SNAT Metrics
```powershell
# Get PLS resource ID
$plsId = az network private-link-service show `
    --resource-group rg-pls-bicep-test `
    --name plstest-provider-pls `
    --query "id" -o tsv

# View in Azure Portal
Start-Process "https://portal.azure.com/#@/resource$plsId/metrics"
```

### Key Metrics to Monitor
- **SNAT Connection Count**: Current active SNAT connections
- **SNAT Port Allocation**: Number of SNAT ports allocated
- **Bytes In/Out**: Traffic throughput
- **Dropped Connections**: Connections dropped due to SNAT exhaustion

## Deployment Scenarios

### Scenario 1: Test 50% SNAT Capacity (2 NAT IPs = 128K ports)
```bash
# 16K per PE = 64K total = 50% of 128K
python3 ~/exhaust_snat_multi_pe.py 16000
```

### Scenario 2: Test 75% SNAT Capacity
```bash
# 24K per PE = 96K total = 75% of 128K
python3 ~/exhaust_snat_multi_pe.py 24000
```

### Scenario 3: Test 90% SNAT Capacity
```bash
# 28.8K per PE = 115.2K total = 90% of 128K
python3 ~/exhaust_snat_multi_pe.py 28800
```

### Scenario 4: Attempt SNAT Exhaustion
```bash
# 32K per PE = 128K total = 100% of 128K (will likely hit limits)
python3 ~/exhaust_snat_multi_pe.py 32000
```

## Multi-VM Testing

To distribute load across multiple client VMs:

### Client VM 1
```bash
ssh azureuser@128.24.110.108
python3 ~/exhaust_snat_multi_pe.py 10000  # 40K total
```

### Client VM 2
```bash
ssh azureuser@172.172.42.213
curl -s https://raw.githubusercontent.com/msrini-MSFT/azd-azure-private-link-service-snat-exhaustion/main/exhaust_snat_multi_pe.py -o ~/exhaust_snat_multi_pe.py
chmod +x ~/exhaust_snat_multi_pe.py
python3 ~/exhaust_snat_multi_pe.py 10000  # 40K total
```

**Combined**: 80K connections = ~62% SNAT usage with 2 NAT IPs

## Troubleshooting

### Issue: "Cannot assign requested address"
- **Cause**: Local ephemeral port exhaustion on client VM
- **Solution**: Reduce connections per PE or tune kernel parameters

### Issue: "Too many open files"
- **Cause**: File descriptor limit too low
- **Solution**: Script automatically raises limits, but check with `ulimit -n`

### Issue: Connections dropping immediately
- **Cause**: Backend server not responding
- **Solution**: Verify server VM is running: `curl -v http://10.0.1.4`

### Issue: Lower than expected connection count
- **Cause**: Network or backend constraints
- **Solution**: Check backend server capacity and NSG rules

## Key Features

✅ **Parallel connection creation** to all 4 PEs simultaneously  
✅ **Automatic resource limit handling**  
✅ **Progress tracking** per PE  
✅ **SNAT usage calculations** for 1 or 2 NAT IPs  
✅ **Persistent connections** held indefinitely until stopped  
✅ **Graceful error handling** for network issues  

## Comparison with Original Script

| Feature | Original | Multi-PE |
|---------|----------|----------|
| Target PEs | 1 (manual IP) | 4 (automatic) |
| Parallelization | No | Yes (4 threads) |
| SNAT Distribution | Single PE | Even across all PEs |
| Max SNAT Usage | 25% (1 PE) | 100% (4 PEs) |
| Progress Tracking | Basic | Per-PE detailed |

## Next Steps

1. **SSH into Client VMs** using passwords from Key Vault
2. **Download the script** from GitHub
3. **Start with small test** (e.g., 1000 connections per PE)
4. **Monitor Azure Portal metrics** for PLS
5. **Gradually increase** connection count
6. **Document results** at different SNAT usage levels
