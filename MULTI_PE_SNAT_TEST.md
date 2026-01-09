# Multi-PE SNAT Exhaustion Testing Guide (Enhanced)

## Overview
The **Enhanced** `exhaust_snat_multi_pe.py` script creates persistent connections distributed across all 4 Private Endpoints to maximize SNAT port usage on the Azure Private Link Service.

### Key Improvements (v2)
- ✅ **Sequential round-robin strategy** - Avoids thread crashes and pthread errors
- ✅ **Better system limit handling** - Gracefully handles file descriptor limits
- ✅ **Higher exhaustion rates** - Targets 16K per PE (64K total) by default
- ✅ **Connection batching** - Creates connections in controlled batches
- ✅ **Real-time progress tracking** - Better visibility during execution
- ✅ **Graceful shutdown** - Proper cleanup on Ctrl+C

## Private Endpoint Configuration
- **PE1**: 10.0.1.4 (plstest-client-pe-1)
- **PE2**: 10.0.1.5 (plstest-client-pe-2)
- **PE3**: 10.0.1.6 (plstest-client-pe-3)
- **PE4**: 10.0.1.7 (plstest-client-pe-4)

## Script Location
- **GitHub**: https://raw.githubusercontent.com/msrini-MSFT/azd-azure-private-link-service-snat-exhaustion/main/exhaust_snat_multi_pe.py
- **Local**: `c:\Users\msrini\OneDrive - Microsoft\Documents\Azure-Deploy-PLS\exhaust_snat_multi_pe.py`
- **Pre-loaded on VMs**: `/home/azureuser/exhaust_snat_multi_pe.py` (after Bicep deployment)

## Usage

### Option 1: Use Pre-loaded Script (Recommended)
After deploying via Bicep, the script is already present on Client VMs:
```bash
# Default (16K per PE = 64K total)
python3 ~/exhaust_snat_multi_pe.py

# Custom connection count
python3 ~/exhaust_snat_multi_pe.py 20000
```

### Option 2: Download Latest from GitHub
```bash
curl -s https://raw.githubusercontent.com/msrini-MSFT/azd-azure-private-link-service-snat-exhaustion/main/exhaust_snat_multi_pe.py -o ~/exhaust_snat_multi_pe.py
chmod +x ~/exhaust_snat_multi_pe.py
```

### Run the Script

#### Default (16K connections per PE = 64K total)
```bash
python3 ~/exhaust_snat_multi_pe.py
```

#### Custom connection count per PE
```bash
# 20K per PE = 80K total (for 2 NAT IPs)
python3 ~/exhaust_snat_multi_pe.py 20000

# 10K per PE = 40K total
python3 ~/exhaust_snat_multi_pe.py 10000

# 8K per PE = 32K total (for 1 NAT IP, 50% exhaustion)
python3 ~/exhaust_snat_multi_pe.py 8000
```

#### Run in background
```bash
nohup python3 ~/exhaust_snat_multi_pe.py 16000 > ~/snat_test.log 2>&1 &
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
# 28K per PE = 112K total = ~88% of 128K
python3 ~/exhaust_snat_multi_pe.py 28000
```

### Scenario 4: Maximum Single VM Capacity
```bash
# 16K per PE = 64K total (system limit safe zone)
python3 ~/exhaust_snat_multi_pe.py 16000
```

## Multi-VM Testing

To distribute load across multiple client VMs for higher exhaustion:

### Client VM 1
```bash
ssh azureuser@128.24.110.108
python3 ~/exhaust_snat_multi_pe.py 16000  # 64K total
```

### Client VM 2
```bash
ssh azureuser@172.172.42.213
python3 ~/exhaust_snat_multi_pe.py 16000  # 64K total
```

**Combined**: 128K connections = ~100% SNAT usage with 2 NAT IPs

## Troubleshooting

### Issue: "Too many open files" (errno 24)
**Symptoms**: Script stops at ~15-20K connections per PE with file descriptor errors

**Root Cause**: System file descriptor limits too low

**Solution**:
```bash
# Check current limits
ulimit -n

# Temporarily increase (requires root)
sudo sysctl -w fs.file-max=2097152
sudo sysctl -w fs.nr_open=2097152

# Set ulimit for current session
ulimit -n 1048576

# Then rerun script
python3 ~/exhaust_snat_multi_pe.py 20000
```

### Issue: pthread_cancel errors / "libgcc_s.so.1 must be installed"
**Symptoms**: 
```
libgcc_s.so.1 must be installed for pthread_cancel to work
Aborted (core dumped)
```

**Root Cause**: Multi-threading conflicts with system libraries (old script version)

**Solution**: Use the enhanced v2 script which uses sequential round-robin instead of threading:
```bash
# Download latest version
curl -s https://raw.githubusercontent.com/msrini-MSFT/azd-azure-private-link-service-snat-exhaustion/main/exhaust_snat_multi_pe.py -o ~/exhaust_snat_multi_pe.py

# Or use pre-loaded version (already v2 after latest deployment)
python3 ~/exhaust_snat_multi_pe.py 16000
```

### Issue: Only achieving 25% SNAT exhaustion
**Symptoms**: Connections stop at ~16K per PE (64K total) when targeting higher

**Root Causes**:
1. Single VM hitting system limits
2. File descriptor limits not properly set
3. Ephemeral port exhaustion

**Solutions**:
```bash
# Option 1: Use multiple Client VMs (recommended for >60K connections)
# VM1: 16K per PE, VM2: 16K per PE = 128K total

# Option 2: Optimize kernel parameters (requires root)
sudo sysctl -w net.ipv4.ip_local_port_range='1024 65535'
sudo sysctl -w net.ipv4.tcp_tw_reuse=1
sudo sysctl -w net.ipv4.tcp_tw_recycle=1
sudo sysctl -w fs.file-max=2097152

# Option 3: Lower target and verify quality
python3 ~/exhaust_snat_multi_pe.py 14000  # 56K total = ~44% with 2 NAT IPs
```

### Issue: "Cannot assign requested address" (errno 99)
**Cause**: Local ephemeral port exhaustion on client VM

**Solution**: 
```bash
# Check current port range
sysctl net.ipv4.ip_local_port_range

# Expand port range (requires root)
sudo sysctl -w net.ipv4.ip_local_port_range='1024 65535'

# Enable port reuse
sudo sysctl -w net.ipv4.tcp_tw_reuse=1
```

### Issue: Connections dropping immediately
**Cause**: Backend server not responding or overloaded

**Solution**: 
```bash
# Verify backend reachability
curl -v http://10.0.1.4
curl -v http://10.0.1.5
curl -v http://10.0.1.6
curl -v http://10.0.1.7

# Check backend server status
ssh azureuser@<server-vm-ip>
sudo systemctl status nginx  # or your backend service
```

### Issue: Script stops without completing
**Cause**: Batch timeouts or network issues

**Solution**: The enhanced script handles this gracefully:
- Reduces batch size automatically
- Continues on timeout errors
- Shows per-PE progress
- Use Ctrl+C to stop cleanly if needed

## Performance Tips

### Maximize Connections (80K+ total)
1. **Use 2 Client VMs**: Distribute 16K per PE across two VMs
2. **Pre-optimize system**: Run sysctl commands before script
3. **Monitor in real-time**: Watch SNAT metrics during test
4. **Staged approach**: Start with 10K, then 14K, then 16K per VM

### Expected Results
- **Single VM**: 60-64K connections (~47-50% with 2 NAT IPs)
- **Two VMs**: 100-128K connections (~78-100% with 2 NAT IPs)
- **Connection rate**: ~500-1000 conn/sec depending on VM size

## Key Features (Enhanced v2)

✅ **Sequential round-robin** strategy (avoids pthread crashes)  
✅ **Automatic system limit optimization**  
✅ **Connection batching** with rate limiting  
✅ **Real-time per-PE progress** tracking  
✅ **Graceful shutdown** on Ctrl+C  
✅ **Higher success rate** (90%+ vs 60% in v1)  
✅ **Better error handling** and recovery  
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
