#!/bin/bash
#
# =====================================
# Multi-Namespace Traffic Generator Lab
# Option-2: One-hop Routing via Linux VM
# =====================================
#
# USAGE:
#   - Create: sudo ./ns_tgen_direct.sh
#   - Delete: sudo ./ns_tgen_direct.sh --delete
#

### CONFIGURATION ###
CLIENT_COUNT=20
SERVER_COUNT=5
CLIENT_BASE_IP="172.16.1"
SERVER_BASE_IP="172.16.2"
CLIENT_START_IP=200
SERVER_START_IP=200

CLIENT_GW_IP="172.16.1.1"
CLIENT_IF="eth1"
CLIENT_BRIDGE="client_br"

SERVER_GW_IP="172.16.2.1"
SERVER_IF="eth2"
SERVER_BRIDGE="server_br"

echo "[+] Checking for lighttpd installation..."
if ! command -v lighttpd &> /dev/null; then
    echo "[+] Installing lighttpd on host..."
    sudo apt update -qq
    sudo apt install -y lighttpd > /dev/null
else
    echo "[+] lighttpd is already installed."
fi

check_ns_exist() {
    ns=$(ip netns list | grep -E "client_ns|server_ns")
    if [[ -n "$ns" ]]; then
        echo "[!] Existing namespaces detected:"
        echo "$ns"
        return 0
    else
        return 1
    fi
}

client_ns_create() {
    echo "[+] Creating client bridge: $CLIENT_BRIDGE"
    ip link add name $CLIENT_BRIDGE type bridge
    ip addr add $CLIENT_BASE_IP.254/24 dev $CLIENT_BRIDGE
    ip link set $CLIENT_BRIDGE up

    echo "    - Attaching $CLIENT_IF to $CLIENT_BRIDGE"
    ip link set $CLIENT_IF master $CLIENT_BRIDGE
    ip link set $CLIENT_IF up

    for i in $(seq 1 $CLIENT_COUNT); do
        NS="client_ns$i"
        VETH="client_ns_if$i"
        VPEER="client_br_if$i"
        IP="$CLIENT_BASE_IP.$((CLIENT_START_IP + i - 1))"

        echo "[+] Creating $NS with IP $IP"
        ip netns add $NS
        ip link add $VETH type veth peer name $VPEER
        ip link set $VETH netns $NS

        ip netns exec $NS ip addr add $IP/24 dev $VETH
        ip netns exec $NS ip link set $VETH up
        ip netns exec $NS ip link set lo up
        ip netns exec $NS ip route add default via $CLIENT_GW_IP

        ip link set $VPEER up
        ip link set $VPEER master $CLIENT_BRIDGE

        ip netns exec $NS bash -c "
            while true; do
                for srv in \$(seq $SERVER_START_IP $((SERVER_START_IP + SERVER_COUNT - 1))); do
                    # Send one ping to the server
                    ping -c 1 $SERVER_BASE_IP.\$srv > /dev/null
                    # Send a curl request
                    curl -s http://$SERVER_BASE_IP.\$srv/index.html > /dev/null
                done
                sleep 2
            done
        " &
        echo "    - $NS created successfully"
    done

    echo "[+] Client namespaces created and connected to $CLIENT_BRIDGE."
}

server_ns_create() {
    echo "[+] Creating server bridge: $SERVER_BRIDGE"
    ip link add name $SERVER_BRIDGE type bridge
    ip addr add $SERVER_BASE_IP.254/24 dev $SERVER_BRIDGE
    ip link set $SERVER_BRIDGE up

    echo "    - Attaching $SERVER_IF to $SERVER_BRIDGE"
    ip link set $SERVER_IF master $SERVER_BRIDGE
    ip link set $SERVER_IF up

    for i in $(seq 1 $SERVER_COUNT); do
        NS="server_ns$i"
        VETH="server_ns_if$i"
        VPEER="server_br_if$i"
        IP="$SERVER_BASE_IP.$((SERVER_START_IP + i - 1))"

        echo "[+] Creating $NS with IP $IP"
        ip netns add $NS
        ip link add $VETH type veth peer name $VPEER
        ip link set $VETH netns $NS

        ip netns exec $NS ip addr add $IP/24 dev $VETH
        ip netns exec $NS ip link set $VETH up
        ip netns exec $NS ip link set lo up
        ip netns exec $NS ip route add default via $SERVER_GW_IP

        ip link set $VPEER up
        ip link set $VPEER master $SERVER_BRIDGE

        ip netns exec $NS bash -c "
            echo '<h1>Hello from $NS</h1>' > /var/www/html/index.html
            lighttpd -D -f /etc/lighttpd/lighttpd.conf &
        "
        echo "    - $NS created successfully"
    done

    echo "[+] Server namespaces created and connected to $SERVER_BRIDGE."
}

client_ns_del() {
    echo "[+] Deleting client namespaces and bridge..."
    for i in $(seq 1 $CLIENT_COUNT); do
        NS="client_ns$i"
        VETH="client_ns_if$i"
        VPEER="client_br_if$i"

        # Delete namespace
        if ip netns list | grep -q $NS; then
            ip netns del $NS
            echo "    - $NS deleted"
        fi

        # Delete bridge-side veth interface (if exists)
        if ip link show | grep -q $VPEER; then
            ip link del $VPEER 2>/dev/null
            echo "    - $VPEER (bridge-side) deleted"
        fi
    done

    # Detach physical interface from bridge
    if ip link show | grep -q $CLIENT_IF; then
        ip link set $CLIENT_IF nomaster
        echo "    - $CLIENT_IF detached from bridge"
    fi

    # Delete bridge
    if ip link show | grep -q $CLIENT_BRIDGE; then
        ip link set $CLIENT_BRIDGE down
        ip link del $CLIENT_BRIDGE
        echo "    - $CLIENT_BRIDGE deleted"
    fi
}

server_ns_del() {
    echo "[+] Deleting server namespaces and bridge..."
    for i in $(seq 1 $SERVER_COUNT); do
        NS="server_ns$i"
        VETH="server_ns_if$i"
        VPEER="server_br_if$i"

        # Delete namespace
        if ip netns list | grep -q $NS; then
            ip netns del $NS
            echo "    - $NS deleted"
        fi

        # Delete bridge-side veth interface (if exists)
        if ip link show | grep -q $VPEER; then
            ip link del $VPEER 2>/dev/null
            echo "    - $VPEER (bridge-side) deleted"
        fi
    done

    # Detach physical interface from bridge
    if ip link show | grep -q $SERVER_IF; then
        ip link set $SERVER_IF nomaster
        echo "    - $SERVER_IF detached from bridge"
    fi

    # Delete bridge
    if ip link show | grep -q $SERVER_BRIDGE; then
        ip link set $SERVER_BRIDGE down
        ip link del $SERVER_BRIDGE
        echo "    - $SERVER_BRIDGE deleted"
    fi
}

if [[ "$1" == "--delete" ]]; then
    if ! check_ns_exist; then
        echo "[!] No relevant namespaces exist to delete."
        exit 1
    fi
    client_ns_del
    server_ns_del
    echo "[+] All namespaces and bridges deleted."
else
    if check_ns_exist; then
        echo "[!] Namespaces already exist. Aborting creation."
        exit 1
    fi
    server_ns_create
    client_ns_create
    echo "[+] All namespaces created and configured."
fi
