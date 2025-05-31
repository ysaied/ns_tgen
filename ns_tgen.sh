#!/bin/bash
# -------------------------------------------------
# Script: ns_tgen.sh
# Description: Setup/teardown of Linux network namespaces
# Supports both routed (L3) and bridged (L2) modes
# Usage: sudo ./ns_tgen.sh [--start | --delete] [-r|-l3|--routed | -b|-l2|--bridged]
# Author: Yasser Saied
# -------------------------------------------------

### CONFIGURATION ###
CLIENT_COUNT=1
SERVER_COUNT=1
CLIENT_BASE_IP="172.16.1"
SERVER_BASE_IP="172.16.2"
CLIENT_START_IP=101
SERVER_START_IP=101
START_TRAFFIC="True"

CLIENT_IRB_GW_IP="172.16.1.1"
CLIENT_IRB_ETH_IF="eth1"
### below parameters is not used in Routed mode
CLIENT_IRB_ETH_IP="172.16.1.254/24"

SERVER_IRB_GW_IP="172.16.2.1"
SERVER_IRB_ETH_IF="eth2"
### below parameters is not used in Routed mode
SERVER_IRB_IF_IP="172.16.2.254/24"

# Default mode ("routed" or "bridged")
MODE="routed"

# Parse mode flags: routed = L3, bridged = L2
for arg in "$@"; do
  case "$arg" in
    -b|--bridged|-l2) MODE="bridged";;
    -r|--routed|-l3) MODE="routed";;
  esac
done

### FUNCTION: Clean up existing namespaces ###
cleanup_namespaces() {
  echo "[-] Cleaning Up"
  ip -all netns delete 2>/dev/null
  pkill -f "bash -c        while true;"
  pkill lighttpd
  pkill dnsmasq
  pkill -f "rsyslogd -n -i /run/rsyslogd-s_"
}

### FUNCTION: Install ARP Ping if not installed ###
install_arping() {
    # Check if the package is installed (dpkg -s returns 0 if installed)
    if ! dpkg -s iputils-arping &>/dev/null; then
        sudo apt-get update > /dev/null
        sudo apt-get install -y iputils-arping > /dev/null
    fi
}

### FUNCTION: Create client IRB namespace ###
create_client_irb() {
  echo "[+] Creating client IRB namespace (c_irb)..."
  ip netns add c_irb
  ip netns exec c_irb sysctl -w net.ipv4.ip_forward=1  &>/dev/null
  ip link set $CLIENT_IRB_ETH_IF netns c_irb

  # Always create the bridge inside c_irb
  ip netns exec c_irb ip link add name c_br type bridge || true
  ip netns exec c_irb ip addr add ${CLIENT_BASE_IP}.254/24 dev c_br
  ip netns exec c_irb ip link set c_br up

  if [ "$MODE" = "routed" ]; then
    ip netns exec c_irb ip addr add $CLIENT_IRB_ETH_IP dev $CLIENT_IRB_ETH_IF
    ip netns exec c_irb ip link set $CLIENT_IRB_ETH_IF up
    ip netns exec c_irb ip route add default via $CLIENT_IRB_GW_IP
    CLIENT_NS_GW_IP=${CLIENT_BASE_IP}.254
  else
    ip netns exec c_irb ip link set $CLIENT_IRB_ETH_IF master c_br
    ip netns exec c_irb ip link set $CLIENT_IRB_ETH_IF up
    CLIENT_NS_GW_IP=$CLIENT_IRB_GW_IP
  fi
}

### FUNCTION: Create server IRB namespace ###
create_server_irb() {
  echo "[+] Creating server IRB namespace (s_irb)..."
  ip netns add s_irb
  ip netns exec s_irb sysctl -w net.ipv4.ip_forward=1 &>/dev/null
  ip link set $SERVER_IRB_ETH_IF netns s_irb

  # Always create the bridge inside s_irb
  ip netns exec s_irb ip link add name s_br type bridge || true
  ip netns exec s_irb ip addr add ${SERVER_BASE_IP}.254/24 dev s_br
  ip netns exec s_irb ip link set s_br up

  if [ "$MODE" = "routed" ]; then
    ip netns exec s_irb ip addr add $SERVER_IRB_IF_IP dev $SERVER_IRB_ETH_IF
    ip netns exec s_irb ip link set $SERVER_IRB_ETH_IF up
    ip netns exec s_irb ip route add default via $SERVER_IRB_GW_IP
    SERVER_NS_GW_IP=${SERVER_BASE_IP}.254
  else
    ip netns exec s_irb ip link set $SERVER_IRB_ETH_IF master s_br
    ip netns exec s_irb ip link set $SERVER_IRB_ETH_IF up
    SERVER_NS_GW_IP=$SERVER_IRB_GW_IP
  fi
}

### FUNCTION: Create client namespaces and attach to bridge ###
create_clients() {
  for i in $(seq 1 $CLIENT_COUNT); do
    echo "[+] Creating client ns c_$i..."
    ip netns add c_$i

    # Create veth pair between c_$i and c_irb
    ip link add c_${i}_if type veth peer name c_br_if${i}
    ip link set c_${i}_if netns c_$i
    ip link set c_br_if${i} netns c_irb

    # Attach the peer to the bridge in c_irb
    ip netns exec c_irb ip link set c_br_if${i} up
    ip netns exec c_irb ip link set c_br_if${i} master c_br

    # Configure IP on the client side
    ip netns exec c_$i ip addr add ${CLIENT_BASE_IP}.$((CLIENT_START_IP + i - 1))/24 dev c_${i}_if
    ip netns exec c_$i ip link set c_${i}_if up
    ip netns exec c_$i arping -c 1 -A -I c_${i}_if ${CLIENT_BASE_IP}.$((CLIENT_START_IP + i - 1)) &>/dev/null
    ip netns exec c_$i ip link set lo up
    ip netns exec c_$i ip route add default via $CLIENT_NS_GW_IP
  done
}

### FUNCTION: Create server namespaces and attach to bridge ###
create_servers() {
  for i in $(seq 1 $SERVER_COUNT); do
    echo "[+] Creating server ns s_$i..."
    ip netns add s_$i

    # Create veth pair between s_$i and s_irb
    ip link add s_${i}_if type veth peer name s_br_if${i}
    ip link set s_${i}_if netns s_$i
    ip link set s_br_if${i} netns s_irb

    # Attach the peer to the bridge in s_irb
    ip netns exec s_irb ip link set s_br_if${i} up
    ip netns exec s_irb ip link set s_br_if${i} master s_br

    # Configure IP on the server side
    ip netns exec s_$i ip addr add ${SERVER_BASE_IP}.$((SERVER_START_IP + i - 1))/24 dev s_${i}_if
    ip netns exec s_$i ip link set s_${i}_if up
    ip netns exec s_$i arping -c 1 -A -I s_${i}_if ${SERVER_BASE_IP}.$((SERVER_START_IP + i - 1)) &>/dev/null
    ip netns exec s_$i ip link set lo up
    ip netns exec s_$i ip route add default via $SERVER_NS_GW_IP
  done
}

### FUNCTION: Start traffic flows ###
start_traffic_flows() {
  if [ "$START_TRAFFIC" != "True" ]; then
    echo "[!] START_TRAFFIC is not set to True — skipping traffic flows."
    return
  fi

  # -------------------------------------------------
  # VERIFY & INSTALL REQUIRED PACKAGES ON HOST
  # -------------------------------------------------
  REQUIRED_PKGS=(lighttpd dnsmasq rsyslogd)
  for PKG in "${REQUIRED_PKGS[@]}"; do
    if ! command -v "$PKG" &> /dev/null; then
      echo "[+] Installing $PKG..."
      apt update -qq
      apt install -y "$PKG" > /dev/null
    fi
  done

  # -------------------------------------------------
  # START LIGHTTPD & DNSMASQ IN SERVER NAMESPACES
  # -------------------------------------------------
  for i in $(seq 1 "$SERVER_COUNT"); do
    NS="s_$i"
    # ----- LIGHTTPD -----
    ip netns exec "$NS" bash -c "
      mkdir -p /var/www/html
      echo \"<h1>Hello from server $NS</h1>\" > /var/www/html/index.html
      lighttpd -D -f /etc/lighttpd/lighttpd.conf &
    "

    # ----- DNSMASQ -----
    mkdir -p "/etc/netns/$NS/dnsmasq.d"
    cat > "/etc/netns/$NS/dnsmasq.d/wildcard.conf" <<EOF
# Catch-all DNS record: answer any query with 1.2.3.4 (change as needed)
address=/#/1.2.3.4
EOF

    ip netns exec "$NS" dnsmasq \
      --no-hosts \
      --no-resolv \
      --conf-dir="/etc/netns/$NS/dnsmasq.d" \
      --pid-file="/run/netns_${NS}.dnsmasq.pid" \
      --keep-in-foreground \
      --log-facility=/dev/null \
      --quiet-dhcp &

    # ----- RSYSLOG-----
    mkdir -p "/etc/netns/$NS"
    cat > "/etc/netns/$NS/rsyslog.conf" <<'EOF'
module(load="imudp") 
input(type="imudp" port="514")
*.*   /dev/null
EOF
    ip netns exec "$NS" rsyslogd -n -i "/run/rsyslogd-$NS.pid" &

  done

  # -------------------------------------------------
  # START CLIENT-SIDE TRAFFIC GENERATION (PING & CURL)
  # -------------------------------------------------
  echo "[+] Starting client-side traffic generation (ping, curl, DNS)..."
  for i in $(seq 1 "$CLIENT_COUNT"); do
    ip netns exec "c_$i" bash -c "
      while true; do
        for j in \$(seq $SERVER_START_IP $((SERVER_START_IP + SERVER_COUNT - 1))); do
          ping -f -c 1 $SERVER_BASE_IP.\$j > /dev/null
          curl -s http://$SERVER_BASE_IP.\$j > /dev/null
          dig google.com +short @$SERVER_BASE_IP.\$j > /dev/null
          logger -n $SERVER_BASE_IP.\$j -P 514 \"Yasser Saied\" > /dev/null
        done
        sleep 2
      done
    " &
  done
}
show_help() {
  cat <<-EOF
Usage: $0 [--start|-s | --delete|-d] [-r|-l3|--routed | -b|-l2|--bridged]

Options:
  -s, --start
        Create namespaces, configure networking and launch traffic.
  -d, --delete
        Delete all namespaces and teardown the setup.
  -r, -l3, --routed
        Run in routed (L3) mode. Assign IPs directly to IRB interfaces.
  -b, -l2, --bridged
        Run in bridged (L2) mode. Attach IRB interfaces to a bridge.

Examples:
  $0 --start --routed
  $0 -s -l2
  $0 --delete

EOF
}



### MAIN ###
case "$1" in
  --start|-s)
    cleanup_namespaces
    install_arping
    echo "[+] Selected mode: $MODE"
    create_client_irb
    create_server_irb
    create_clients
    create_servers
    start_traffic_flows
    echo "[+] Setup complete."
    ;;
  --delete|-d)
    cleanup_namespaces
    echo "[+] Teardown complete."
    ;;
  *)
    show_help
    exit 1

    ;;
esac
