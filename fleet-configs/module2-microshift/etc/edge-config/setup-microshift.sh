#!/bin/bash
# Fleet Manager Configuration Script - MicroShift VRRP Gateways
# Delivered by flightctl-agent to /etc/edge-config/setup-microshift.sh
# Triggered by edge-config-microshift.service systemd unit.
#
# Configures: hostname, dynamic IP discovery, /etc/hosts, firewall,
# MicroShift, keepalived with VRRP VIP, and kubeconfig.

set -euo pipefail

ROLE_FILE="/etc/edge-config/device-role"
LOCK="/var/run/edge-config-microshift.done"
LOG="/var/log/edge-config-microshift.log"
VIP="10.102.0.100"

exec > >(tee -a "$LOG") 2>&1

[ -f "$LOCK" ] && { echo "Already configured. Remove $LOCK to re-run."; exit 0; }

if [ ! -f "$ROLE_FILE" ]; then
    echo "ERROR: $ROLE_FILE not found. Cannot determine gateway role."
    exit 1
fi

ROLE=$(cat "$ROLE_FILE")

case "$ROLE" in
    gw-a)
        HOSTNAME="microshift-gw-a"
        PEER_HOSTNAME="microshift-gw-b"
        KEEPALIVED_STATE="MASTER"
        KEEPALIVED_PRIORITY="100"
        ;;
    gw-b)
        HOSTNAME="microshift-gw-b"
        PEER_HOSTNAME="microshift-gw-a"
        KEEPALIVED_STATE="BACKUP"
        KEEPALIVED_PRIORITY="90"
        ;;
    *)
        echo "ERROR: Unknown role '$ROLE'. Expected 'gw-a' or 'gw-b'."
        exit 1
        ;;
esac

echo "=== MicroShift VRRP Setup: role=$ROLE hostname=$HOSTNAME state=$KEEPALIVED_STATE ==="

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
grep -q "$VIP microshift-vip" /etc/hosts 2>/dev/null || echo "$VIP microshift-vip" >> /etc/hosts

# Discover peer via ARP scan on the L2 segment
PEER_IP=""
for attempt in $(seq 1 60); do
    for candidate in $(seq 11 254); do
        CANDIDATE_IP=$(echo "$MY_IP" | sed "s/\.[0-9]*$/.$candidate/")
        [ "$CANDIDATE_IP" = "$MY_IP" ] && continue
        [ "$CANDIDATE_IP" = "$VIP" ] && continue
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

# Keepalived configuration
mkdir -p /etc/keepalived
cat > /etc/keepalived/keepalived.conf << KEEPALIVED_EOF
vrrp_script check_microshift {
    script "/usr/bin/curl -k -s https://localhost:6443/readyz"
    interval 3
    weight -20
    fall 2
    rise 2
}

vrrp_instance MICROSHIFT_VIP {
    state ${KEEPALIVED_STATE}
    interface eth1
    virtual_router_id 1
    priority ${KEEPALIVED_PRIORITY}
    advert_int 1

    authentication {
        auth_type PASS
        auth_pass microshift123
    }

    virtual_ipaddress {
        ${VIP}/24 dev eth1
    }

    track_script {
        check_microshift
    }
}
KEEPALIVED_EOF

# Firewall rules
systemctl enable --now firewalld
firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
firewall-cmd --permanent --zone=trusted --add-source=169.254.169.1
firewall-cmd --permanent --zone=public --add-port=6443/tcp
firewall-cmd --permanent --zone=public --add-port=80/tcp
firewall-cmd --permanent --zone=public --add-port=443/tcp
firewall-cmd --permanent --zone=public --add-port=5353/udp
firewall-cmd --permanent --add-protocol=vrrp
firewall-cmd --reload

# Start MicroShift
systemctl enable --now microshift

for i in $(seq 1 60); do
    if curl -k -s https://localhost:6443/readyz &>/dev/null; then
        echo "MicroShift is ready"
        break
    fi
    echo "Waiting for MicroShift... ($i/60)"
    sleep 5
done

# Set up kubeconfig for cloud-user
mkdir -p /home/cloud-user/.kube
cp /var/lib/microshift/resources/kubeadmin/kubeconfig /home/cloud-user/.kube/config
chown -R cloud-user:cloud-user /home/cloud-user/.kube
chmod 600 /home/cloud-user/.kube/config

# Start Keepalived (after MicroShift so health check can work)
systemctl enable --now keepalived

# Start the status web dashboard
systemctl daemon-reload
systemctl enable --now gateway-status-web.service || true

touch "$LOCK"
echo "=== MicroShift VRRP configuration complete for $HOSTNAME ==="
