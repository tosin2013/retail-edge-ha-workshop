#!/bin/bash
# Fleet Manager Configuration Script - Two-Node OpenShift Simulated Cluster
# Delivered by flightctl-agent to /etc/edge-config/setup-twonode.sh
# Triggered by edge-config-twonode.service systemd unit.
#
# Configures: hostname, dynamic IP discovery, /etc/hosts (all 3 nodes),
# and basic connectivity verification. Module 3 uses RHCOS + Ignition
# so this script handles post-boot coordination only.

set -euo pipefail

ROLE_FILE="/etc/edge-config/device-role"
LOCK="/var/run/edge-config-twonode.done"
LOG="/var/log/edge-config-twonode.log"

exec > >(tee -a "$LOG") 2>&1

[ -f "$LOCK" ] && { echo "Already configured. Remove $LOCK to re-run."; exit 0; }

if [ ! -f "$ROLE_FILE" ]; then
    echo "ERROR: $ROLE_FILE not found. Cannot determine node role."
    exit 1
fi

ROLE=$(cat "$ROLE_FILE")

case "$ROLE" in
    master1)
        HOSTNAME="twonode-master1"
        ;;
    master2)
        HOSTNAME="twonode-master2"
        ;;
    arbiter)
        HOSTNAME="twonode-arbiter"
        ;;
    *)
        echo "ERROR: Unknown role '$ROLE'. Expected 'master1', 'master2', or 'arbiter'."
        exit 1
        ;;
esac

echo "=== Two-Node OCP Setup: role=$ROLE hostname=$HOSTNAME ==="

hostnamectl set-hostname "$HOSTNAME"

# Discover own IP on the UDN interface (eth1, assigned by OVN DHCP)
for attempt in $(seq 1 30); do
    MY_IP=$(ip -4 addr show eth1 2>/dev/null | grep -oP 'inet \K[0-9.]+' || true)
    [ -n "$MY_IP" ] && break
    echo "Waiting for eth1 IP assignment... ($attempt/30)"
    sleep 5
done

if [ -z "$MY_IP" ]; then
    echo "ERROR: Could not obtain IP on eth1 after 150s."
    exit 1
fi

echo "My IP: $MY_IP"

grep -q "$MY_IP $HOSTNAME" /etc/hosts 2>/dev/null || echo "$MY_IP $HOSTNAME" >> /etc/hosts

# Discover peers via ARP scan (expect 2 other nodes on the L2 segment)
ALL_ROLES=("master1" "master2" "arbiter")
ALL_HOSTNAMES=("twonode-master1" "twonode-master2" "twonode-arbiter")
DISCOVERED=0

echo "Scanning for peers on L2 segment..."
for attempt in $(seq 1 60); do
    for candidate in $(seq 11 254); do
        CANDIDATE_IP=$(echo "$MY_IP" | sed "s/\.[0-9]*$/.$candidate/")
        [ "$CANDIDATE_IP" = "$MY_IP" ] && continue
        if arping -c 1 -w 1 -I eth1 "$CANDIDATE_IP" &>/dev/null; then
            if ! grep -q "$CANDIDATE_IP" /etc/hosts 2>/dev/null; then
                echo "Discovered peer at $CANDIDATE_IP"
                DISCOVERED=$((DISCOVERED + 1))
                # We cannot determine peer role from IP alone; write IP for now
                echo "$CANDIDATE_IP peer-$DISCOVERED" >> /etc/hosts
            fi
        fi
    done
    PEER_COUNT=$(grep -c "^[0-9]" /etc/hosts 2>/dev/null | head -1 || echo 0)
    [ "$PEER_COUNT" -ge 3 ] && break
    echo "Found $((PEER_COUNT - 1)) peers so far, retrying... ($attempt/60)"
    sleep 5
done

echo "Peer discovery complete. /etc/hosts:"
cat /etc/hosts

# Start the status web dashboard
systemctl daemon-reload
systemctl enable cluster-status-web.service || true
systemctl start --no-block cluster-status-web.service || true

touch "$LOCK"
echo "=== Two-Node OCP configuration complete for $HOSTNAME ==="
