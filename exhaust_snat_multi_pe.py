#!/usr/bin/env python3
"""
SNAT Port Exhaustion Test - Multi Private Endpoint
Creates persistent connections distributed across multiple Private Endpoints
to maximize SNAT port usage on Azure Private Link Service.

Usage: python3 exhaust_snat_multi_pe.py [CONNECTIONS_PER_PE]
"""

import socket
import sys
import time
import resource
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed

# Private Endpoint IPs (auto-configured for plstest-client-pe-1 through pe-4)
PE_IPS = [
    "10.0.1.4",  # plstest-client-pe-1
    "10.0.1.5",  # plstest-client-pe-2
    "10.0.1.6",  # plstest-client-pe-3
    "10.0.1.7"   # plstest-client-pe-4
]

PORT = 80
CONNECTIONS_PER_PE = 15000  # Default: 60K total connections (15K x 4 PEs)

def set_limits():
    """Increase the number of open files allowed"""
    soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    print(f"Current limits: soft={soft}, hard={hard}")
    try:
        resource.setrlimit(resource.RLIMIT_NOFILE, (hard, hard))
        new_soft, new_hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        print(f"New limits: soft={new_soft}, hard={new_hard}")
    except Exception as e:
        print(f"Failed to set limits: {e}")

def connect_to_pe(pe_ip, port, count, pe_index):
    """
    Establish and hold connections to a specific Private Endpoint.
    
    Args:
        pe_ip: Private Endpoint IP address
        port: Target port (typically 80)
        count: Number of connections to establish
        pe_index: PE identifier for logging (1-4)
    
    Returns:
        List of active socket objects
    """
    sockets = []
    print(f"[PE{pe_index}] Starting to connect to {pe_ip}:{port} (target: {count} connections)")
    
    for i in range(count):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.settimeout(5)
            s.connect((pe_ip, port))
            
            # Send HTTP request header to keep connection active
            s.send(b"GET / HTTP/1.1\r\nHost: localhost\r\n")
            s.setblocking(False)
            sockets.append(s)
            
            if (i + 1) % 1000 == 0:
                print(f"[PE{pe_index}] Established {i + 1}/{count} connections to {pe_ip}")
                sys.stdout.flush()
                
        except socket.timeout:
            print(f"[PE{pe_index}] Connection {i} timed out")
            time.sleep(0.1)
        except OSError as e:
            if e.errno in [99, 24, 98]:  # Cannot assign address, Too many files, Address in use
                print(f"[PE{pe_index}] Hit system limit at {i} connections: {e}")
                break
            print(f"[PE{pe_index}] Error at connection {i}: {e}")
            time.sleep(0.1)
        except Exception as e:
            print(f"[PE{pe_index}] Unexpected error at connection {i}: {e}")
            break
    
    established = len(sockets)
    print(f"[PE{pe_index}] ✓ Holding {established}/{count} connections to {pe_ip}")
    return sockets

def main():
    """Main execution function"""
    # Parse command line arguments
    connections_per_pe = CONNECTIONS_PER_PE
    if len(sys.argv) > 1:
        try:
            connections_per_pe = int(sys.argv[1])
        except ValueError:
            print(f"Invalid connection count. Using default: {CONNECTIONS_PER_PE}")
    
    total_target = connections_per_pe * len(PE_IPS)
    
    print("=" * 70)
    print("SNAT Port Exhaustion Test - Multi Private Endpoint")
    print("=" * 70)
    print(f"Target Private Endpoints: {len(PE_IPS)}")
    for idx, ip in enumerate(PE_IPS, 1):
        print(f"  PE{idx}: {ip}")
    print(f"\nConnections per PE: {connections_per_pe}")
    print(f"Total target connections: {total_target}")
    print(f"Port: {PORT}")
    print("=" * 70)
    print()
    
    # Set system limits
    set_limits()
    print()
    
    # Use ThreadPoolExecutor to connect to all PEs in parallel
    all_sockets = []
    start_time = time.time()
    
    with ThreadPoolExecutor(max_workers=len(PE_IPS)) as executor:
        futures = {
            executor.submit(connect_to_pe, pe_ip, PORT, connections_per_pe, idx): idx
            for idx, pe_ip in enumerate(PE_IPS, 1)
        }
        
        for future in as_completed(futures):
            pe_idx = futures[future]
            try:
                sockets = future.result()
                all_sockets.extend(sockets)
                print(f"[PE{pe_idx}] Thread completed")
            except Exception as e:
                print(f"[PE{pe_idx}] Thread failed: {e}")
    
    elapsed = time.time() - start_time
    total_established = len(all_sockets)
    
    print()
    print("=" * 70)
    print("CONNECTION SUMMARY")
    print("=" * 70)
    print(f"Total connections established: {total_established}/{total_target}")
    print(f"Success rate: {(total_established/total_target)*100:.1f}%")
    print(f"Time taken: {elapsed:.2f} seconds")
    print(f"Connection rate: {total_established/elapsed:.0f} conn/sec")
    print()
    print("Estimated SNAT usage:")
    print(f"  With 1 NAT IP (64K ports): {(total_established/64000)*100:.1f}%")
    print(f"  With 2 NAT IPs (128K ports): {(total_established/128000)*100:.1f}%")
    print("=" * 70)
    print()
    print("Holding connections open. Press Ctrl+C to stop...")
    
    # Keep connections alive indefinitely
    try:
        while True:
            time.sleep(30)
            # Optional: Send periodic keep-alive
            # for s in all_sockets:
            #     try:
            #         s.send(b"X-Keep: 1\r\n")
            #     except:
            #         pass
    except KeyboardInterrupt:
        print("\n\nShutting down...")
        for s in all_sockets:
            try:
                s.close()
            except:
                pass
        print(f"Closed {len(all_sockets)} connections")

if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Fatal error: {e}")
        sys.exit(1)
