#!/bin/bash
# =============================================================================
# Configure Automatic RHEL Subscription for OpenShift Virtualization VMs
# =============================================================================
# Patches the kubevirt-ui-features ConfigMap so that new RHEL VMs are
# automatically registered with Red Hat via activation key + org ID.
#
# This is a PREREQUISITE for the workshop — run it once during deployment.
#
# The activation key and org ID can be provided via:
#   1. Environment variables: RHEL_ACTIVATION_KEY, RHEL_ORG_ID
#   2. CLI arguments: --activation-key <key> --org-id <id>
#   3. AgnosticD secrets (agnosticd-v2-secrets/<account>.yml):
#        rhel_activation_key: "<key>"
#        rhel_org_id: "<id>"
#
# Prerequisites:
#   - oc CLI authenticated as cluster-admin
#   - OpenShift Virtualization installed
#   - A Red Hat activation key from https://access.redhat.com/management/activation_keys
#
# Usage:
#   ./scripts/configure-rhel-subscription.sh --activation-key <key> --org-id <id>
#   RHEL_ACTIVATION_KEY=<key> RHEL_ORG_ID=<id> ./scripts/configure-rhel-subscription.sh
# =============================================================================

set -euo pipefail

ACTIVATION_KEY="${RHEL_ACTIVATION_KEY:-}"
ORG_ID="${RHEL_ORG_ID:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --activation-key) ACTIVATION_KEY="$2"; shift 2 ;;
    --org-id)         ORG_ID="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: $0 --activation-key <key> --org-id <id>"
      echo "   or: RHEL_ACTIVATION_KEY=<key> RHEL_ORG_ID=<id> $0"
      exit 0 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

if [[ -z "$ACTIVATION_KEY" || -z "$ORG_ID" ]]; then
  echo "ERROR: Both --activation-key and --org-id are required."
  echo ""
  echo "Create an activation key at:"
  echo "  https://access.redhat.com/management/activation_keys"
  echo ""
  echo "Usage:"
  echo "  $0 --activation-key <key> --org-id <id>"
  exit 1
fi

echo "=========================================="
echo "Configuring RHEL VM Auto-Subscription"
echo "=========================================="
echo "Activation Key:  ${ACTIVATION_KEY}"
echo "Organization ID: ${ORG_ID}"
echo ""

if ! oc whoami &>/dev/null; then
  echo "ERROR: Not logged in to OpenShift. Run 'oc login' first."
  exit 1
fi

CONFIGMAP="kubevirt-ui-features"
NAMESPACE="openshift-cnv"

if ! oc get configmap "$CONFIGMAP" -n "$NAMESPACE" &>/dev/null; then
  echo "ERROR: ConfigMap ${NAMESPACE}/${CONFIGMAP} not found."
  echo "Is OpenShift Virtualization installed?"
  exit 1
fi

echo "Patching ConfigMap ${NAMESPACE}/${CONFIGMAP}..."
oc patch configmap "$CONFIGMAP" -n "$NAMESPACE" --type merge -p "$(cat <<EOF
{
  "data": {
    "automaticSubscriptionActivationKey": "${ACTIVATION_KEY}",
    "automaticSubscriptionOrganizationId": "${ORG_ID}",
    "automaticSubscriptionType": "monitorAndManageSubscriptions"
  }
}
EOF
)"

echo ""
echo "Verifying configuration..."
STORED_KEY=$(oc get configmap "$CONFIGMAP" -n "$NAMESPACE" -o jsonpath='{.data.automaticSubscriptionActivationKey}')
STORED_ORG=$(oc get configmap "$CONFIGMAP" -n "$NAMESPACE" -o jsonpath='{.data.automaticSubscriptionOrganizationId}')

if [[ "$STORED_KEY" == "$ACTIVATION_KEY" && "$STORED_ORG" == "$ORG_ID" ]]; then
  echo "Auto-subscription configured successfully!"
else
  echo "WARNING: Stored values don't match. Check the ConfigMap manually:"
  echo "  oc get configmap $CONFIGMAP -n $NAMESPACE -o yaml"
  exit 1
fi

echo ""
echo "=========================================="
echo "RHEL VM Auto-Subscription Ready"
echo "=========================================="
echo ""
echo "New RHEL VMs will now automatically register with Red Hat."
echo "Existing VMs need to be recreated (delete + ArgoCD sync) to pick up this change."
echo ""
echo "To verify in the UI:"
echo "  Virtualization → Overview → Settings → Guest management"
echo "  → Automatic subscription of new RHEL VirtualMachines"
