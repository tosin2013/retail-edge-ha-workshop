#!/bin/bash
# Fleet Manager Configuration Script - Pacemaker HA Nodes
# This script is pushed to devices by Red Hat Edge Manager via fleet config.
# It configures hostname, /etc/hosts, hacluster password, and pcsd service.
#
# The flightctl agent places this file on the device; a systemd path unit
# triggers execution when the file arrives.

set -euo pipefail

ROLE_FILE="/etc/edge-config/device-role"
LOCK="/var/run/edge-config-pacemaker.done"

[ -f "$LOCK" ] && exit 0

if [ ! -f "$ROLE_FILE" ]; then
    echo "ERROR: $ROLE_FILE not found. Cannot determine node role."
    exit 1
fi

ROLE=$(cat "$ROLE_FILE")

case "$ROLE" in
    node1)
        HOSTNAME="rhel-ha-node1"
        IP="10.101.0.20"
        ;;
    node2)
        HOSTNAME="rhel-ha-node2"
        IP="10.101.0.21"
        ;;
    *)
        echo "ERROR: Unknown role '$ROLE'. Expected 'node1' or 'node2'."
        exit 1
        ;;
esac

echo "Configuring Pacemaker HA: role=$ROLE hostname=$HOSTNAME ip=$IP"

hostnamectl set-hostname "$HOSTNAME"

grep -q "10.101.0.20 rhel-ha-node1" /etc/hosts || echo "10.101.0.20 rhel-ha-node1" >> /etc/hosts
grep -q "10.101.0.21 rhel-ha-node2" /etc/hosts || echo "10.101.0.21 rhel-ha-node2" >> /etc/hosts

echo "redhat" | passwd --stdin hacluster

systemctl enable --now pcsd

touch "$LOCK"
echo "Pacemaker HA configuration complete for $HOSTNAME"
