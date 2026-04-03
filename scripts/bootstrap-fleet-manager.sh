#!/bin/bash
# =============================================================================
# Bootstrap Fleet Manager (Red Hat Edge Manager) for Workshop
# =============================================================================
# This script configures Fleet Manager with:
#   1. A Repository pointing to the workshop Git repo
#   2. Fleet definitions for Module 1 (Pacemaker HA) and Module 2 (MicroShift VRRP)
#
# Prerequisites:
#   - flightctl CLI installed (see Module 0 for install instructions)
#   - oc CLI authenticated to the OpenShift cluster
#   - Edge Manager deployed and healthy
#
# Usage:
#   ./scripts/bootstrap-fleet-manager.sh
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
FLEET_DEFS_DIR="${REPO_ROOT}/fleet-definitions"
FLEET_MGMT_DIR="${REPO_ROOT}/fleet-management"
VALUES_FILE="${REPO_ROOT}/helm/retail-edge-ha/values.yaml"

echo "=========================================="
echo "Bootstrapping Fleet Manager"
echo "=========================================="

# Determine cluster domain from values.yaml or oc
if command -v yq &>/dev/null; then
  CLUSTER_DOMAIN=$(yq '.global.clusterDomain' "$VALUES_FILE" 2>/dev/null)
else
  CLUSTER_DOMAIN=$(grep 'clusterDomain:' "$VALUES_FILE" | head -1 | awk '{print $2}')
fi

if [[ -z "$CLUSTER_DOMAIN" ]]; then
  echo "ERROR: Could not determine cluster domain from values.yaml"
  exit 1
fi

EDGE_MANAGER_API="api.redhat-edge-manager.${CLUSTER_DOMAIN}"
echo "Edge Manager API: ${EDGE_MANAGER_API}"

if ! command -v flightctl &>/dev/null; then
  echo "ERROR: flightctl CLI not found. Install it first:"
  echo "  CLI_POD=\$(oc get pods -n redhat-edge-manager -o name | grep cli-artifacts)"
  echo "  oc exec -n redhat-edge-manager \${CLI_POD#pod/} -- cat /home/server/src/gh-archives/amd64/linux/flightctl-linux-amd64.tar.gz > /tmp/flightctl.tar.gz"
  echo "  tar xzf /tmp/flightctl.tar.gz -C /usr/local/bin/"
  exit 1
fi

echo ""
echo "Step 1: Login to Edge Manager"
OC_TOKEN=$(oc whoami -t 2>/dev/null || true)
if [[ -z "$OC_TOKEN" ]]; then
  echo "ERROR: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

flightctl login "https://${EDGE_MANAGER_API}" -k --token="${OC_TOKEN}"
echo ""

echo "Step 2: Apply repository"
echo "  Applying: repository.yaml"
flightctl apply -f "${FLEET_MGMT_DIR}/repository.yaml"
echo ""

echo "Step 3: Apply fleet definitions"
for f in "${FLEET_DEFS_DIR}"/*.yaml; do
  fname=$(basename "$f")
  echo "  Applying: ${fname}"
  flightctl apply -f "$f"
done
echo ""

echo "Step 4: Verify resources"
echo ""
echo "Repositories:"
flightctl get repositories
echo ""
echo "Fleets:"
flightctl get fleets
echo ""

echo "Step 5: Apply ResourceSync (enables GitOps for fleet definitions)"
echo "  Applying: resourcesync.yaml"
flightctl apply -f "${FLEET_MGMT_DIR}/resourcesync.yaml"
echo ""
echo "ResourceSyncs:"
flightctl get resourcesyncs

echo ""
echo "=========================================="
echo "Fleet Manager bootstrap complete!"
echo "=========================================="
echo ""
echo "Fleets created:"
echo "  - pacemaker-ha     (matches devices with label module=pacemaker)"
echo "  - microshift-vrrp  (matches devices with label module=microshift)"
echo ""
echo "When students start VMs, devices will:"
echo "  1. Auto-enroll with Edge Manager"
echo "  2. Match a fleet via labels"
echo "  3. Receive configuration from the Git repo"
echo ""
echo "Next: Start VMs with 'virtctl start' and watch enrollment:"
echo "  flightctl get enrollmentrequests"
echo "  flightctl get devices"
