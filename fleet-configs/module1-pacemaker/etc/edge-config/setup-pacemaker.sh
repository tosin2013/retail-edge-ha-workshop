#!/bin/bash
# Fleet Manager Configuration Script - Pacemaker HA Nodes
# Delivered by flightctl-agent to /etc/edge-config/setup-pacemaker.sh
# Triggered by edge-config-pacemaker.service systemd unit.
#
# Configures: hostname, dynamic IP discovery, /etc/hosts (with peer wait),
# hacluster password, pcsd, and pre-installs GFS2/DLM packages for the
# shared-storage exercise.

set -euo pipefail

ROLE_FILE="/etc/edge-config/device-role"
LOCK="/var/run/edge-config-pacemaker.done"
LOG="/var/log/edge-config-pacemaker.log"

exec > >(tee -a "$LOG") 2>&1

[ -f "$LOCK" ] && { echo "Already configured. Remove $LOCK to re-run."; exit 0; }

if [ ! -f "$ROLE_FILE" ]; then
    echo "ERROR: $ROLE_FILE not found. Cannot determine node role."
    exit 1
fi

ROLE=$(cat "$ROLE_FILE")

case "$ROLE" in
    node1)
        HOSTNAME="rhel-ha-node1"
        PEER_HOSTNAME="rhel-ha-node2"
        ;;
    node2)
        HOSTNAME="rhel-ha-node2"
        PEER_HOSTNAME="rhel-ha-node1"
        ;;
    *)
        echo "ERROR: Unknown role '$ROLE'. Expected 'node1' or 'node2'."
        exit 1
        ;;
esac

echo "=== Pacemaker HA Setup: role=$ROLE hostname=$HOSTNAME ==="

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

# Discover peer via ARP scan on the L2 segment
SUBNET=$(echo "$MY_IP" | sed 's/\.[0-9]*$/.0\/24/')
echo "Scanning $SUBNET for peer (excluding self $MY_IP)..."

PEER_IP=""
for attempt in $(seq 1 60); do
    for candidate in $(seq 11 254); do
        CANDIDATE_IP=$(echo "$MY_IP" | sed "s/\.[0-9]*$/.$candidate/")
        [ "$CANDIDATE_IP" = "$MY_IP" ] && continue
        if arping -c 1 -w 1 -I eth1 "$CANDIDATE_IP" &>/dev/null; then
            PEER_IP="$CANDIDATE_IP"
            break 2
        fi
    done
    echo "Peer not found yet, retrying... ($attempt/60)"
    sleep 5
done

if [ -n "$PEER_IP" ]; then
    echo "Peer discovered: $PEER_IP ($PEER_HOSTNAME)"
    grep -q "$PEER_IP $PEER_HOSTNAME" /etc/hosts 2>/dev/null || echo "$PEER_IP $PEER_HOSTNAME" >> /etc/hosts
else
    echo "WARNING: Peer not discovered after 300s. /etc/hosts may need manual update."
fi

echo "redhat" | passwd --stdin hacluster

systemctl enable --now pcsd

# Pre-install GFS2 and DLM packages for the shared-storage exercise (Step 11)
dnf install -y gfs2-utils dlm lvm2-lockd || echo "WARNING: Some storage packages failed to install"
systemctl enable dlm || true

# Start the status web dashboard
systemctl daemon-reload
systemctl enable --now ha-status-web.service || true

touch "$LOCK"
echo "=== Pacemaker HA configuration complete for $HOSTNAME ==="
