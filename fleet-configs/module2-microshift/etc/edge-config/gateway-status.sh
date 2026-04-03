#!/bin/bash
# MicroShift VRRP Gateway Status Dashboard
# Deployed via Fleet Manager to /etc/edge-config/gateway-status.sh
# Run manually: /etc/edge-config/gateway-status.sh
# Or via HTTP:  curl http://<vm-ip>:8080

set -o pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'
VIP="10.102.0.100"

status_icon() {
    if [ "$1" = "ok" ]; then echo -e "${GREEN}[OK]${NC}"
    elif [ "$1" = "warn" ]; then echo -e "${YELLOW}[WARN]${NC}"
    else echo -e "${RED}[FAIL]${NC}"
    fi
}

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║         MicroShift VRRP Gateway Status Dashboard            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Node Identity
HOSTNAME=$(hostname)
MY_IP=$(ip -4 addr show eth1 2>/dev/null | grep -oP 'inet \K[0-9.]+' | head -1 || echo "N/A")
echo -e "${BOLD}Node:${NC} $HOSTNAME ($MY_IP)"
echo -e "${BOLD}Time:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# MicroShift Status
echo -e "${BOLD}── MicroShift ──${NC}"
if systemctl is-active --quiet microshift 2>/dev/null; then
    echo -e "  Service:    $(status_icon ok) Active"
else
    echo -e "  Service:    $(status_icon fail) Inactive"
fi

if curl -k -s --max-time 3 https://localhost:6443/readyz &>/dev/null; then
    echo -e "  API (6443): $(status_icon ok) Healthy"
else
    echo -e "  API (6443): $(status_icon fail) Not responding"
fi

# Pod status (if kubeconfig available)
KUBECONFIG_PATH="/home/cloud-user/.kube/config"
if [ -f "$KUBECONFIG_PATH" ]; then
    POD_COUNT=$(KUBECONFIG="$KUBECONFIG_PATH" oc get pods -A --no-headers 2>/dev/null | wc -l || echo 0)
    RUNNING=$(KUBECONFIG="$KUBECONFIG_PATH" oc get pods -A --no-headers 2>/dev/null | grep -c "Running" || echo 0)
    echo -e "  Pods:       ${RUNNING}/${POD_COUNT} running"
fi
echo ""

# Keepalived / VRRP
echo -e "${BOLD}── Keepalived / VRRP ──${NC}"
if systemctl is-active --quiet keepalived 2>/dev/null; then
    echo -e "  Service:    $(status_icon ok) Active"
else
    echo -e "  Service:    $(status_icon fail) Inactive"
fi

HAS_VIP=$(ip -4 addr show eth1 2>/dev/null | grep -c "$VIP" || echo 0)
if [ "$HAS_VIP" -gt 0 ]; then
    echo -e "  VIP ($VIP): $(status_icon ok) MASTER - VIP is on this node"
else
    echo -e "  VIP ($VIP): $(status_icon warn) BACKUP - VIP is on peer"
fi

VRRP_STATE=$(journalctl -u keepalived --no-pager -n 50 2>/dev/null \
    | grep -oP '(Entering|entering) (MASTER|BACKUP|FAULT) STATE' | tail -1 || echo "Unknown")
echo -e "  VRRP State: $VRRP_STATE"
echo ""

# Peer Connectivity
echo -e "${BOLD}── Peer Connectivity ──${NC}"
PEER_HOSTNAME=""
if [ "$HOSTNAME" = "microshift-gw-a" ]; then
    PEER_HOSTNAME="microshift-gw-b"
else
    PEER_HOSTNAME="microshift-gw-a"
fi

PEER_IP=$(getent hosts "$PEER_HOSTNAME" 2>/dev/null | awk '{print $1}')
if [ -n "$PEER_IP" ]; then
    if ping -c 1 -W 2 "$PEER_IP" &>/dev/null; then
        echo -e "  $PEER_HOSTNAME ($PEER_IP): $(status_icon ok) Reachable"
    else
        echo -e "  $PEER_HOSTNAME ($PEER_IP): $(status_icon fail) Unreachable"
    fi
else
    echo -e "  $PEER_HOSTNAME: $(status_icon warn) Not in /etc/hosts"
fi

if ping -c 1 -W 2 "$VIP" &>/dev/null; then
    echo -e "  VIP ($VIP):     $(status_icon ok) Reachable"
else
    echo -e "  VIP ($VIP):     $(status_icon warn) Unreachable"
fi
echo ""

# Firewall
echo -e "${BOLD}── Firewall ──${NC}"
if systemctl is-active --quiet firewalld 2>/dev/null; then
    echo -e "  Firewalld:  $(status_icon ok) Active"
    VRRP_OK=$(firewall-cmd --list-protocols 2>/dev/null | grep -c vrrp || echo 0)
    if [ "$VRRP_OK" -gt 0 ]; then
        echo -e "  VRRP Proto: $(status_icon ok) Allowed"
    else
        echo -e "  VRRP Proto: $(status_icon fail) Not in firewall rules"
    fi
else
    echo -e "  Firewalld:  $(status_icon warn) Not running"
fi
echo ""

# Fleet Manager Agent
echo -e "${BOLD}── Fleet Manager Agent ──${NC}"
if systemctl is-active --quiet flightctl-agent 2>/dev/null; then
    echo -e "  Agent:      $(status_icon ok) Running"
else
    echo -e "  Agent:      $(status_icon warn) Not running"
fi
echo ""
echo -e "${CYAN}─────────────────────────────────────────────────────────────────${NC}"
