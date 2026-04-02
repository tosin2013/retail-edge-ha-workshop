#!/bin/bash
# Fleet Manager Configuration Script - MicroShift VRRP Gateways
# This script is pushed to devices by Red Hat Edge Manager via fleet config.
# It configures hostname, /etc/hosts, firewall, MicroShift, keepalived, and kubeconfig.
#
# The flightctl agent places this file on the device; a systemd path unit
# triggers execution when the file arrives.

set -euo pipefail

ROLE_FILE="/etc/edge-config/device-role"
LOCK="/var/run/edge-config-microshift.done"

[ -f "$LOCK" ] && exit 0

if [ ! -f "$ROLE_FILE" ]; then
    echo "ERROR: $ROLE_FILE not found. Cannot determine gateway role."
    exit 1
fi

ROLE=$(cat "$ROLE_FILE")

case "$ROLE" in
    gw-a)
        HOSTNAME="microshift-gw-a"
        IP="10.102.0.20"
        KEEPALIVED_STATE="MASTER"
        KEEPALIVED_PRIORITY="100"
        ;;
    gw-b)
        HOSTNAME="microshift-gw-b"
        IP="10.102.0.21"
        KEEPALIVED_STATE="BACKUP"
        KEEPALIVED_PRIORITY="90"
        ;;
    *)
        echo "ERROR: Unknown role '$ROLE'. Expected 'gw-a' or 'gw-b'."
        exit 1
        ;;
esac

echo "Configuring MicroShift VRRP: role=$ROLE hostname=$HOSTNAME ip=$IP state=$KEEPALIVED_STATE"

hostnamectl set-hostname "$HOSTNAME"

grep -q "10.102.0.20 microshift-gw-a" /etc/hosts || echo "10.102.0.20 microshift-gw-a" >> /etc/hosts
grep -q "10.102.0.21 microshift-gw-b" /etc/hosts || echo "10.102.0.21 microshift-gw-b" >> /etc/hosts
grep -q "10.102.0.100 microshift-vip" /etc/hosts || echo "10.102.0.100 microshift-vip" >> /etc/hosts

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
        10.102.0.100/24 dev eth1
    }

    track_script {
        check_microshift
    }
}
KEEPALIVED_EOF

systemctl enable --now firewalld
firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
firewall-cmd --permanent --zone=trusted --add-source=169.254.169.1
firewall-cmd --permanent --zone=public --add-port=6443/tcp
firewall-cmd --permanent --zone=public --add-port=80/tcp
firewall-cmd --permanent --zone=public --add-port=443/tcp
firewall-cmd --permanent --zone=public --add-port=5353/udp
firewall-cmd --permanent --add-protocol=vrrp
firewall-cmd --reload

systemctl enable --now microshift

for i in $(seq 1 60); do
    if curl -k -s https://localhost:6443/readyz &>/dev/null; then
        echo "MicroShift is ready"
        break
    fi
    echo "Waiting for MicroShift... ($i/60)"
    sleep 5
done

mkdir -p /home/cloud-user/.kube
cp /var/lib/microshift/resources/kubeadmin/kubeconfig /home/cloud-user/.kube/config
chown -R cloud-user:cloud-user /home/cloud-user/.kube
chmod 600 /home/cloud-user/.kube/config

systemctl enable --now keepalived

cat > /home/cloud-user/test-deployment.sh << 'SCRIPT'
#!/bin/bash
oc create deployment nginx --image=nginx --replicas=2
oc expose deployment nginx --port=80 --type=NodePort
echo "Test deployment created. Access via: curl http://10.102.0.100:<nodeport>"
SCRIPT
chmod +x /home/cloud-user/test-deployment.sh
chown cloud-user:cloud-user /home/cloud-user/test-deployment.sh

touch "$LOCK"
echo "MicroShift VRRP configuration complete for $HOSTNAME"
