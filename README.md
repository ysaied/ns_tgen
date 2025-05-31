# Network Namespace Traffic Generator (ns_tgen)

A lightweight shell script to create network namespaces, simulate client-server traffic, and run simple services (HTTP, DNS, Syslog) within namespaces. Useful for testing network setups or traffic flows entirely on a single Linux host.

## Features

- Create client and server namespaces with either **routed (L3)** or **bridged (L2)** mode.
- Launch lightweight services in server namespaces:
  - HTTP server (lighttpd) serving a simple index page.
  - DNS server (dnsmasq) with a wildcard entry to respond with a fixed IP.
  - Syslog server (rsyslogd) listening on UDP 514 (logs discarded).
- Generate continuous traffic from client namespaces:
  - `ping` floods to server IPs.
  - `curl` HTTP requests.
  - `logger` syslog messages.
- One-command install of required host packages (`lighttpd`, `dnsmasq`, `rsyslog`).
- Easy start/stop via `--start`/`--delete` flags.
- **MIT License**—free to use and contribute!

## Requirements

- Linux with support for network namespaces (`ip netns`).
- Root privileges (or sudo) to create namespaces and install packages.
- `bash`, `ip`, `apt-get`, `lighttpd`, `dnsmasq`, `rsyslogd`.

## Usage

```bash
# Clone or download this script to your host machine
chmod +x ns_tgen.sh

# Start namespaces in routed (L3) mode and launch services:
sudo ./ns_tgen.sh --start --routed

# Start namespaces in bridged (L2) mode:
sudo ./ns_tgen.sh --start --bridged

# Delete all namespaces and cleanup:
sudo ./ns_tgen.sh --delete
```

For more details on flags:

```bash
./ns_tgen.sh --help
```

## Script Overview

```bash
#!/bin/bash
# -------------------------------------------------
# ns_tgen.sh - Network Namespace Traffic Generator
#
# Copyright (c) 2025 Your Name
#
# MIT License
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Feel free to enhance or improve. Contributions welcome!
# -------------------------------------------------

### CONFIGURATION ###
SERVER_COUNT=10      # Number of server namespaces (s_1, s_2, ..., s_10)
CLIENT_COUNT=1       # Number of client namespaces (c_1, c_2, etc.)
CLIENT_BASE_IP="192.168.10"
SERVER_BASE_IP="192.168.20"
CLIENT_START_IP=11
SERVER_START_IP=11
START_TRAFFIC="True"

# Default mode ("routed" or "bridged")
MODE="routed"

# Parse mode flags: routed = L3, bridged = L2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --start|-s)
      ACTION="start"
      shift
      ;;
    --delete|-d)
      ACTION="delete"
      shift
      ;;
    -r|--routed|-l3|--l3)
      MODE="routed"
      shift
      ;;
    -b|--bridged|-l2|--l2)
      MODE="bridged"
      shift
      ;;
    -h|--help)
      echo "Usage: $0 [--start|-s | --delete|-d] [-r|-l3|--routed | -b|-l2|--bridged]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 [--start|-s | --delete|-d] [-r|-l3|--routed | -b|-l2|--bridged]"
      exit 1
      ;;
  esac
done

### FUNCTION: Clean up existing namespaces ###
cleanup_namespaces() {
  echo "[+] Deleting any existing namespaces..."
  ip -all netns delete 2>/dev/null || true
}

### FUNCTION: Create client IRB namespace ###
create_client_irb() {
  echo "[+] Creating client IRB namespace (c_irb)…"
  ip netns add c_irb
  ip netns exec c_irb sysctl -w net.ipv4.ip_forward=1
  ip link set eth1 netns c_irb

  # Always create the bridge inside c_irb
  ip netns exec c_irb ip link add name c_br type bridge || true
  ip netns exec c_irb ip link set c_br up

  if [ "$MODE" = "routed" ]; then
    echo "    → Configuring routed (L3) in c_irb"
    ip netns exec c_irb ip addr add 172.16.1.254/24 dev eth1
    ip netns exec c_irb ip link set eth1 up
    ip netns exec c_irb ip route add default via 172.16.1.1
  else
    echo "    → Configuring bridged (L2) in c_irb"
    ip netns exec c_irb ip link set eth1 master c_br
    ip netns exec c_irb ip link set eth1 up
    ip netns exec c_irb ip addr add 172.16.1.254/24 dev c_br
  fi
}

### FUNCTION: Create server IRB namespace ###
create_server_irb() {
  echo "[+] Creating server IRB namespace (s_irb)…"
  ip netns add s_irb
  ip netns exec s_irb sysctl -w net.ipv4.ip_forward=1
  ip link set eth2 netns s_irb

  # Always create the bridge inside s_irb
  ip netns exec s_irb ip link add name s_br type bridge || true
  ip netns exec s_irb ip link set s_br up

  if [ "$MODE" = "routed" ]; then
    echo "    → Configuring routed (L3) in s_irb"
    ip netns exec s_irb ip addr add 172.16.2.254/24 dev eth2
    ip netns exec s_irb ip link set eth2 up
    ip netns exec s_irb ip route add default via 172.16.2.1
  else
    echo "    → Configuring bridged (L2) in s_irb"
    ip netns exec s_irb ip link set eth2 master s_br
    ip netns exec s_irb ip link set eth2 up
    ip netns exec s_irb ip addr add 172.16.2.254/24 dev s_br
  fi
}

### FUNCTION: Create client namespaces ###
create_clients() {
  for i in $(seq 1 $CLIENT_COUNT); do
    echo "[+] Creating client ns c_$i…"
    ip netns add c_$i

    # veth pair: c_i ↔ c_br_ifi
    ip link add c_${i}_if type veth peer name c_br_if${i}
    ip link set c_${i}_if netns c_$i
    ip link set c_br_if${i} netns c_irb

    # Attach peer to c_br in c_irb
    ip netns exec c_irb ip link set c_br_if${i} up
    ip netns exec c_irb ip link set c_br_if${i} master c_br

    # Configure IP for c_i
    ip netns exec c_$i ip addr add ${CLIENT_BASE_IP}.$((CLIENT_START_IP + i - 1))/24 dev c_${i}_if
    ip netns exec c_$i ip link set c_${i}_if up
    ip netns exec c_$i ip link set lo up
    ip netns exec c_$i ip route add default via ${CLIENT_BASE_IP}.254
  done
}

### FUNCTION: Create server namespaces ###
create_servers() {
  for i in $(seq 1 $SERVER_COUNT); do
    echo "[+] Creating server ns s_$i…"
    ip netns add s_$i

    # veth pair: s_i ↔ s_br_ifi
    ip link add s_${i}_if type veth peer name s_br_if${i}
    ip link set s_${i}_if netns s_$i
    ip link set s_br_if${i} netns s_irb

    # Attach peer to s_br in s_irb
    ip netns exec s_irb ip link set s_br_if${i} up
    ip netns exec s_irb ip link set s_br_if${i} master s_br

    # Configure IP for s_i
    ip netns exec s_$i ip addr add ${SERVER_BASE_IP}.$((SERVER_START_IP + i - 1))/24 dev s_${i}_if
    ip netns exec s_$i ip link set s_${i}_if up
    ip netns exec s_$i ip link set lo up
    ip netns exec s_$i ip route add default via ${SERVER_BASE_IP}.254
  done
}

### FUNCTION: Start traffic flows ###
start_traffic_flows() {
  if [ "$START_TRAFFIC" != "True" ]; then
    echo "[!] START_TRAFFIC is not set to True — skipping traffic flows."
    return
  fi

  # 1) VERIFY & INSTALL REQUIRED PACKAGES
  echo "[+] Verifying required packages on the host..."
  REQUIRED_PKGS=(lighttpd dnsmasq rsyslog)
  for PKG in "${REQUIRED_PKGS[@]}"; do
    echo -n "    • Checking for $PKG… "
    if ! command -v "$PKG" &> /dev/null; then
      echo "not found. Installing $PKG..."
      apt-get update -qq
      apt-get install -y "$PKG" > /dev/null
    else
      echo "already installed."
    fi
  done

  # 2) LAUNCH LIGHTTPD, DNSMASQ & RSYSLOG IN SERVER NAMESPACES
  echo "[+] Starting services in server namespaces..."
  WILDCARD_DNS_RECORD='# Catch-all DNS record: answer any query with 1.2.3.4
address=/#/1.2.3.4'
  for i in $(seq 1 "$SERVER_COUNT"); do
    NS="s_$i"
    echo "    → Setting up services in namespace $NS..."

    # LIGHTTPD
    ip netns exec "$NS" bash -c '
      mkdir -p /var/www/html
      cat > /var/www/html/index.html <<EOF
<h1>Hello from server '"$NS"'</h1>
EOF
      lighttpd -D -f /etc/lighttpd/lighttpd.conf &
    '

    # DNSMASQ
    mkdir -p "/etc/netns/$NS/dnsmasq.d"
    printf "%b
" "$WILDCARD_DNS_RECORD" > "/etc/netns/$NS/dnsmasq.d/wildcard.conf"
    ip netns exec "$NS" dnsmasq       --no-resolv       --no-hosts       --conf-dir="/etc/netns/$NS/dnsmasq.d"       --pid-file="/run/netns_${NS}.dnsmasq.pid"       --keep-in-foreground       --log-facility=/dev/null       --quiet &

    # RSYSLOG (logs to /dev/null)
    mkdir -p "/etc/netns/$NS"
    cat > "/etc/netns/$NS/rsyslog.conf" <<'EOF'
module(load="imudp")
input(type="imudp" port="514")
*.*    /dev/null
EOF
    ip netns exec "$NS" rsyslogd -n -i "/run/rsyslogd-$NS.pid" &

    echo "[+] $NS: all services started."
  done

  # 3) START CLIENT-SIDE TRAFFIC GENERATION
  echo "[+] Starting client-side traffic generation (ping & curl loops)..."
  for i in $(seq 1 "$CLIENT_COUNT"); do
    ip netns exec "c_$i" bash -c '
      while true; do
        for j in '"$SERVER_START_IP:$((SERVER_START_IP + SERVER_COUNT - 1))"'; do
          ping -f -c 10 '"$SERVER_BASE_IP"'.`printf "%d" "$j"` &> /dev/null
          curl -s http://'"$SERVER_BASE_IP"'.`printf "%d" "$j"` &> /dev/null
        done
        sleep 2
      done
    ' &
  done
}

### MAIN ###
case "$ACTION" in
  start)
    cleanup_namespaces
    create_client_irb
    create_server_irb
    create_clients
    create_servers
    start_traffic_flows
    echo "[+] Setup complete."
    ;;
  delete)
    cleanup_namespaces
    echo "[+] Teardown complete."
    ;;
  *)
    echo "Usage: $0 [--start|-s | --delete|-d] [-r|-l3|--routed | -b|-l2|--bridged]"
    exit 1
    ;;
esac
```
