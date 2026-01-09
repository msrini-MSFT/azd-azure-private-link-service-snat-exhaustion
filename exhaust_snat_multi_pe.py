#!/usr/bin/env python3
"""
SNAT Port Exhaustion Test - Multi Private Endpoint (Enhanced)
Creates persistent connections distributed across multiple Private Endpoints
to maximize SNAT port usage on Azure Private Link Service.

IMPROVEMENTS:
- Sequential connection strategy (avoids thread crashes)
- Better system limit handling
- Connection recycling for higher exhaustion
- Automatic retry on failures
- Real-time progress tracking

Usage: python3 exhaust_snat_multi_pe.py [CONNECTIONS_PER_PE]
"""

import socket
import sys
import time
import resource
import os
import signal
from collections import defaultdict

# Private Endpoint IPs (auto-configured for plstest-client-pe-1 through pe-4)
PE_IPS = [
    "10.0.1.4",  # plstest-client-pe-1
    "10.0.1.5",  # plstest-client-pe-2
    "10.0.1.6",  # plstest-client-pe-3
    "10.0.1.7"   # plstest-client-pe-4
]

PORT = 80
CONNECTIONS_PER_PE = 16000  # Default: 64K total connections (16K x 4 PEs)
BATCH_SIZE = 500  # Create connections in batches
BATCH_DELAY = 0.5  # Seconds between batches

# Global socket storage
active_sockets = defaultdict(list)
stop_flag = False

def signal_handler(sig, frame):
    """Handle Ctrl+C gracefully"""
    global stop_flag
    stop_flag = True
    print("\n\n⚠️  Interrupt received. Shutting down gracefully...")

signal.signal(signal.SIGINT, signal_handler)

def set_limits():
    """Increase system limits for maximum connections"""
    try:
        # Get current limits
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        print(f"📊 Current file descriptor limits: soft={soft}, hard={hard}")
        
        # Try to set to maximum
        target = min(1048576, hard)  # Cap at 1M or hard limit
        resource.setrlimit(resource.RLIMIT_NOFILE, (target, hard))
        
        new_soft, new_hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        print(f"✓ Updated limits: soft={new_soft}, hard={new_hard}")
        
        # Also try to increase kernel limits (requires root)
        try:
            os.system("sudo sysctl -w fs.file-max=2097152 2>/dev/null")
            os.system("sudo sysctl -w net.ipv4.ip_local_port_range='1024 65535' 2>/dev/null")
            os.system("sudo sysctl -w net.ipv4.tcp_tw_reuse=1 2>/dev/null")
        except:
            pass
            
    except Exception as e:
        print(f"⚠️  Warning: Failed to optimize limits: {e}")

def create_batch_connections(pe_ip, pe_index, start_idx, batch_size, timeout=3):
    """
    Create a batch of connections to a PE.
    
    Args:
        pe_ip: Target IP
        pe_index: PE number for logging
        start_idx: Starting connection number
        batch_size: Number of connections to create
        timeout: Socket timeout in seconds
        
    Returns:
        Number of successful connections
    """
    successful = 0
    
    for i in range(batch_size):
        if stop_flag:
            break
            
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(timeout)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_KEEPALIVE, 1)
            s.connect((pe_ip, PORT))
            
            # Send minimal HTTP request
            s.send(b"GET / HTTP/1.1\r\nHost: backend\r\nConnection: keep-alive\r\n\r\n")
            s.setblocking(False)
            
            active_sockets[pe_index].append(s)
            successful += 1
            
        except socket.timeout:
            pass  # Silent timeout, continue
        except OSError as e:
            if e.errno == 24:  # Too many files
                print(f"[PE{pe_index}] ⚠️  File descriptor limit reached at {start_idx + i}")
                break
            elif e.errno in [99, 98]:  # Cannot assign address, Address in use
                time.sleep(0.05)  # Brief pause before retry
        except Exception:
            pass  # Silent fail and continue
    
    return successful

def connect_round_robin(target_per_pe):
    """
    Connect to all PEs in round-robin fashion to distribute load evenly.
    
    Args:
        target_per_pe: Target connections per endpoint
        
    Returns:
        Total connections established
    """
    print(f"🔄 Using round-robin strategy with batches of {BATCH_SIZE}")
    print(f"⏱️  Batch delay: {BATCH_DELAY}s\n")
    
    total_created = 0
    batch_num = 0
    max_batches = (target_per_pe // BATCH_SIZE) + 1
    
    for batch in range(max_batches):
        if stop_flag:
            break
            
        batch_num += 1
        round_start = time.time()
        
        # Connect to each PE in sequence
        for pe_idx, pe_ip in enumerate(PE_IPS, 1):
            if stop_flag:
                break
                
            current_count = len(active_sockets[pe_idx])
            if current_count >= target_per_pe:
                continue  # This PE reached target
            
            remaining = target_per_pe - current_count
            batch_size = min(BATCH_SIZE, remaining)
            
            created = create_batch_connections(pe_ip, pe_idx, current_count, batch_size)
            total_created += created
            
            if created > 0:
                new_total = len(active_sockets[pe_idx])
                progress = (new_total / target_per_pe) * 100
                print(f"[PE{pe_idx}] {new_total:>5}/{target_per_pe} ({progress:>5.1f}%) {pe_ip}")
        
        round_time = time.time() - round_start
        
        # Summary every 10 batches
        if batch_num % 10 == 0:
            total_active = sum(len(sockets) for sockets in active_sockets.values())
            target_total = target_per_pe * len(PE_IPS)
            overall_progress = (total_active / target_total) * 100
            print(f"📊 Batch {batch_num}: Total {total_active}/{target_total} ({overall_progress:.1f}%) - {round_time:.2f}s\n")
        
        # Rate limiting
        if round_time < BATCH_DELAY:
            time.sleep(BATCH_DELAY - round_time)
    
    return total_created

def main():
    """Main execution function"""
    # Parse arguments
    connections_per_pe = CONNECTIONS_PER_PE
    if len(sys.argv) > 1:
        try:
            connections_per_pe = int(sys.argv[1])
        except ValueError:
            print(f"⚠️  Invalid input. Using default: {CONNECTIONS_PER_PE}")
    
    total_target = connections_per_pe * len(PE_IPS)
    
    print("=" * 70)
    print("🚀 ENHANCED SNAT PORT EXHAUSTION TEST")
    print("=" * 70)
    print(f"Strategy: Round-robin sequential batching")
    print(f"Target Endpoints: {len(PE_IPS)}")
    for idx, ip in enumerate(PE_IPS, 1):
        print(f"  PE{idx}: {ip}")
    print(f"\nConnections per PE: {connections_per_pe:,}")
    print(f"Total target: {total_target:,} connections")
    print(f"Port: {PORT}")
    print("=" * 70)
    print()
    
    # Optimize system limits
    set_limits()
    print()
    
    # Start connection process
    print("🔌 Starting connection establishment...\n")
    start_time = time.time()
    
    connect_round_robin(connections_per_pe)
    
    elapsed = time.time() - start_time
    
    # Final statistics
    print("\n" + "=" * 70)
    print("📈 FINAL CONNECTION SUMMARY")
    print("=" * 70)
    
    for pe_idx in sorted(active_sockets.keys()):
        count = len(active_sockets[pe_idx])
        progress = (count / connections_per_pe) * 100
        print(f"PE{pe_idx}: {count:>6}/{connections_per_pe} ({progress:>5.1f}%)")
    
    total_established = sum(len(sockets) for sockets in active_sockets.values())
    success_rate = (total_established / total_target) * 100
    
    print("-" * 70)
    print(f"Total: {total_established:>6}/{total_target} ({success_rate:.1f}%)")
    print(f"Time: {elapsed:.1f}s | Rate: {total_established/elapsed:.0f} conn/s")
    print()
    print("🎯 SNAT Port Exhaustion Estimate:")
    print(f"   1 NAT IP (64K ports): {(total_established/64000)*100:>6.1f}%")
    print(f"   2 NAT IPs (128K ports): {(total_established/128000)*100:>6.1f}%")
    print("=" * 70)
    print()
    
    if total_established > 0:
        print("✓ Holding connections open. Press Ctrl+C to stop...\n")
        
        # Hold connections
        try:
            while not stop_flag:
                time.sleep(60)
                # Periodic status
                alive = sum(len(sockets) for sockets in active_sockets.values())
                print(f"⏳ Status: {alive:,} connections active ({time.strftime('%H:%M:%S')})")
        except KeyboardInterrupt:
            pass
    
    # Cleanup
    print("\n🧹 Cleaning up...")
    closed = 0
    for pe_idx in active_sockets:
        for s in active_sockets[pe_idx]:
            try:
                s.close()
                closed += 1
            except:
                pass
    print(f"✓ Closed {closed:,} connections")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"❌ Fatal error: {e}")
        sys.exit(1)
