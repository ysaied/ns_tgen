#!/bin/bash
#
# =====================================
# Multi-Namespace Traffic Generator Lab
# Option-2: One-hop Routing via Linux VM
# =====================================
#
# USAGE:
#   - Create: sudo ./ns_tgen_routed.sh
#   - Delete: sudo ./ns_tgen_routed.sh --delete
#

### CONFIGURATION ###
CLIENT_COUNT=20
SERVER_COUNT=5
CLIENT_BASE_IP="192.168.10"
SERVER_BASE_IP="192.168.20"
CLIENT_START_IP=200
SERVER_START_IP=200

CLIENT_GW_IP="172.16.1.1"
CLIENT_IF_IP="172.16.1.254/24"
CLIENT_IF="eth1"
CLIENT_BRIDGE="client_br"

SERVER_GW_IP="172.16.2.1"
SERVER_IF_IP="172.16.2.254/24"
SERVER_IF="eth2"
SERVER_BRIDGE="server_br"

### INSTALL LIGHTTPD IF NEEDED ###
check_lighttpd() {
  if ! command -v lighttpd &> /dev/null; then
    echo "[+] Installing lighttpd..."
    apt update -qq
    apt install -y lighttpd > /dev/null
  else
    echo "[+] lighttpd is already installed."
  fi
}

### ENABLE IP FORWARDING ###
enable_ip_forwarding() {
  echo "[+] Enabling IP forwarding..."
  echo 1 > /proc/sys/net/ipv4/ip_forward
}

### ASSIGN IPs TO PHYSICAL INTERFACES ###
assign_if_ips() {
  echo "[+] Assigning IP $CLIENT_IF_IP to $CLIENT_IF..."
  ip addr add $CLIENT_IF_IP dev $CLIENT_IF

  echo "[+] Assigning IP $SERVER_IF_IP to $SERVER_IF..."
  ip addr add $SERVER_IF_IP dev $SERVER_IF
}

### REMOVE IPs FROM PHYSICAL INTERFACES ###
remove_if_ips() {
  echo "[+] Removing IP $CLIENT_IF_IP from $CLIENT_IF..."
  ip addr del $CLIENT_IF_IP dev $CLIENT_IF

  echo "[+] Removing IP $SERVER_IF_IP from $SERVER_IF..."
  ip addr del $SERVER_IF_IP dev $SERVER_IF
}

### ADD STATIC ROUTES ###
add_static_routes() {
  echo "[+] Adding static route for server subnet via DUT on client side..."
  ip route add $SERVER_BASE_IP.0/24 via $CLIENT_GW_IP dev $CLIENT_IF

  echo "[+] Adding static route for client subnet via DUT on server side..."
  ip route add $CLIENT_BASE_IP.0/24 via $SERVER_GW_IP dev $SERVER_IF
}

### REMOVE STATIC ROUTES ###
remove_static_routes() {
  echo "[+] Removing static route for server subnet via DUT on client side..."
  ip route del $SERVER_BASE_IP.0/24 via $CLIENT_GW_IP dev $CLIENT_IF

  echo "[+] Removing static route for client subnet via DUT on server side..."
  ip route del $CLIENT_BASE_IP.0/24 via $SERVER_GW_IP dev $SERVER_IF
}

### CLIENT NAMESPACE CREATION ###
client_ns_create() {
  echo "[+] Creating client bridge: $CLIENT_BRIDGE"
  ip link add name $CLIENT_BRIDGE type bridge
  ip addr add $CLIENT_BASE_IP.254/24 dev $CLIENT_BRIDGE
  ip link set $CLIENT_BRIDGE up

  for i in $(seq 1 $CLIENT_COUNT); do
    NS="client_ns$i"
    VETH="client_ns_if$i"
    VPEER="client_br_if$i"
    IP="$CLIENT_BASE_IP.$((CLIENT_START_IP + i - 1))"

    echo "    [+] Creating $NS with IP $IP"
    ip netns add $NS
    ip link add $VETH type veth peer name $VPEER
    ip link set $VETH netns $NS

    ip netns exec $NS ip addr add $IP/24 dev $VETH
    ip netns exec $NS ip link set $VETH up
    ip netns exec $NS ip link set lo up
    ip netns exec $NS ip route add default via $CLIENT_BASE_IP.254

    ip link set $VPEER up
    ip link set $VPEER master $CLIENT_BRIDGE

    ip netns exec $NS bash -c "
      while true; do
        for srv in \$(seq $SERVER_START_IP $((SERVER_START_IP + SERVER_COUNT - 1))); do
          echo \"[client_ns$i] Pinging $SERVER_BASE_IP.\$srv...\"
          ping -c 1 $SERVER_BASE_IP.\$srv > /dev/null
          echo \"[client_ns$i] Curling $SERVER_BASE_IP.\$srv...\"
          curl -s http://$SERVER_BASE_IP.\$srv/index.html > /dev/null
        done
        sleep 2
      done
    " &
    echo "    - $NS created and active"
  done
  echo "[+] Client namespaces created and connected to $CLIENT_BRIDGE."
}

### SERVER NAMESPACE CREATION ###
server_ns_create() {
  echo "[+] Creating server bridge: $SERVER_BRIDGE"
  ip link add name $SERVER_BRIDGE type bridge
  ip addr add $SERVER_BASE_IP.254/24 dev $SERVER_BRIDGE
  ip link set $SERVER_BRIDGE up

  for i in $(seq 1 $SERVER_COUNT); do
    NS="server_ns$i"
    VETH="server_ns_if$i"
    VPEER="server_br_if$i"
    IP="$SERVER_BASE_IP.$((SERVER_START_IP + i - 1))"

    echo "    [+] Creating $NS with IP $IP"
    ip netns add $NS
    ip link add $VETH type veth peer name $VPEER
    ip link set $VETH netns $NS

    ip netns exec $NS ip addr add $IP/24 dev $VETH
    ip netns exec $NS ip link set $VETH up
    ip netns exec $NS ip link set lo up
    ip netns exec $NS ip route add default via $SERVER_BASE_IP.254

    ip link set $VPEER up
    ip link set $VPEER master $SERVER_BRIDGE

    ip netns exec $NS bash -c "
      echo '<h1>Hello from $NS</h1>' > /var/www/html/index.html
      lighttpd -D -f /etc/lighttpd/lighttpd.conf &
    "
    echo "    - $NS created and active"
  done
  echo "[+] Server namespaces created and connected to $SERVER_BRIDGE."
}

### CLIENT NAMESPACE DELETION ###
client_ns_del() {
  echo "[+] Deleting client namespaces and bridge..."
  for i in $(seq 1 $CLIENT_COUNT); do
    NS="client_ns$i"
    VPEER="client_br_if$i"

    if ip netns list | grep -q $NS; then
      ip netns del $NS
      echo "    - $NS deleted"
    fi
    if ip link show | grep -q $VPEER; then
      ip link del $VPEER 2>/dev/null
      echo "    - $VPEER (bridge-side) deleted"
    fi
  done

  ip link set $CLIENT_BRIDGE down
  ip link del $CLIENT_BRIDGE
  echo "    - $CLIENT_BRIDGE deleted"
}

### SERVER NAMESPACE DELETION ###
server_ns_del() {
  echo "[+] Deleting server namespaces and bridge..."
  for i in $(seq 1 $SERVER_COUNT); do
    NS="server_ns$i"
    VPEER="server_br_if$i"

    if ip netns list | grep -q $NS; then
      ip netns del $NS
      echo "    - $NS deleted"
    fi
    if ip link show | grep -q $VPEER; then
      ip link del $VPEER 2>/dev/null
      echo "    - $VPEER (bridge-side) deleted"
    fi
  done

  ip link set $SERVER_BRIDGE down
  ip link del $SERVER_BRIDGE
  echo "    - $SERVER_BRIDGE deleted"
}

### MAIN ###
if [[ "$1" == "--delete" ]]; then
  echo "[+] Deleting everything..."
  remove_static_routes
  remove_if_ips
  client_ns_del
  server_ns_del
  echo "[+] Cleanup complete."
else
  echo "[+] Starting creation steps..."
  check_lighttpd
  assign_if_ips
  enable_ip_forwarding
  add_static_routes
  server_ns_create
  client_ns_create
  echo "[+] All namespaces and routes created and configured."
fi
