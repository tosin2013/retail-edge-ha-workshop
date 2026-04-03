#!/bin/bash
# Pacemaker HA Cluster Status Dashboard
# Deployed via Fleet Manager to /etc/edge-config/ha-status.sh
# Run manually: /etc/edge-config/ha-status.sh
# Or via HTTP:  curl http://<vm-ip>:8080

set -o pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

status_icon() {
    if [ "$1" = "ok" ]; then echo -e "${GREEN}[OK]${NC}"
    elif [ "$1" = "warn" ]; then echo -e "${YELLOW}[WARN]${NC}"
    else echo -e "${RED}[FAIL]${NC}"
    fi
}

echo -e "${BOLD}${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║          Pacemaker HA Cluster Status Dashboard              ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Node Identity
HOSTNAME=$(hostname)
MY_IP=$(ip -4 addr show eth1 2>/dev/null | grep -oP 'inet \K[0-9.]+' || echo "N/A")
echo -e "${BOLD}Node:${NC} $HOSTNAME ($MY_IP)"
echo -e "${BOLD}Time:${NC} $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# Cluster Status
echo -e "${BOLD}── Cluster Status ──${NC}"
if systemctl is-active --quiet pacemaker 2>/dev/null; then
    echo -e "  Pacemaker:  $(status_icon ok) Active"
else
    echo -e "  Pacemaker:  $(status_icon fail) Inactive"
fi

if systemctl is-active --quiet corosync 2>/dev/null; then
    echo -e "  Corosync:   $(status_icon ok) Active"
else
    echo -e "  Corosync:   $(status_icon fail) Inactive"
fi

if systemctl is-active --quiet pcsd 2>/dev/null; then
    echo -e "  PCSD:       $(status_icon ok) Active"
else
    echo -e "  PCSD:       $(status_icon fail) Inactive"
fi
echo ""

# PCS Status (if cluster is running)
if pcs status &>/dev/null; then
    echo -e "${BOLD}── PCS Cluster Overview ──${NC}"
    pcs status | head -20
    echo ""

    echo -e "${BOLD}── Resources ──${NC}"
    pcs status resources 2>/dev/null || echo "  No resources configured"
    echo ""

    echo -e "${BOLD}── Fencing (STONITH) ──${NC}"
    pcs stonith status 2>/dev/null || echo "  No fencing configured"
    echo ""
else
    echo -e "  $(status_icon warn) Cluster not yet formed (pcs status unavailable)"
    echo ""
fi

# Shared Storage (GFS2)
echo -e "${BOLD}── Shared Storage (GFS2) ──${NC}"
if mount | grep -q gfs2; then
    MOUNT_POINT=$(mount | grep gfs2 | awk '{print $3}')
    echo -e "  GFS2 Mount: $(status_icon ok) Mounted at $MOUNT_POINT"
    df -h "$MOUNT_POINT" 2>/dev/null | tail -1 | awk '{printf "  Disk Usage: %s used of %s (%s)\n", $3, $2, $5}'
    if touch "${MOUNT_POINT}/.status-test" 2>/dev/null && rm -f "${MOUNT_POINT}/.status-test" 2>/dev/null; then
        echo -e "  Write Test: $(status_icon ok) Read/write OK"
    else
        echo -e "  Write Test: $(status_icon fail) Cannot write"
    fi
elif [ -b /dev/vdb ]; then
    echo -e "  GFS2 Mount: $(status_icon warn) Shared disk present (/dev/vdb) but not mounted"
else
    echo -e "  GFS2 Mount: $(status_icon warn) No shared disk attached yet (Step 11)"
fi

if rpm -q gfs2-utils &>/dev/null; then
    echo -e "  Packages:   $(status_icon ok) gfs2-utils installed"
else
    echo -e "  Packages:   $(status_icon warn) gfs2-utils not installed"
fi

if rpm -q dlm &>/dev/null; then
    echo -e "  DLM:        $(status_icon ok) dlm installed"
else
    echo -e "  DLM:        $(status_icon warn) dlm not installed"
fi
echo ""

# Peer Connectivity
echo -e "${BOLD}── Peer Connectivity ──${NC}"
PEER_HOSTNAME=""
if [ "$HOSTNAME" = "rhel-ha-node1" ]; then
    PEER_HOSTNAME="rhel-ha-node2"
else
    PEER_HOSTNAME="rhel-ha-node1"
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
