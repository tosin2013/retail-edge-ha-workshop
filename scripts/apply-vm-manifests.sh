#!/bin/bash
# apply-vm-manifests.sh — Apply generated VM manifests to the cluster
# with RHEL subscription credentials injected at apply time.
#
# Credentials are read from (in order of precedence):
#   1. Environment variables: RHEL_ACTIVATION_KEY, RHEL_ORG_ID
#   2. Kubernetes Secret: rhel-subscription-creds (in openshift-cnv namespace)
#   3. ConfigMap: kubevirt-ui-features (in openshift-cnv namespace)
#
# Credentials NEVER touch Git — manifests have REPLACE_ placeholders.
#
# Usage:
#   ./scripts/apply-vm-manifests.sh [module]
#   module: 1, 2, 3, or all (default: all)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MANIFESTS_DIR="${REPO_ROOT}/manifests/vms"

MODULE="${1:-all}"

# --- Resolve credentials ---
RHEL_ACTIVATION_KEY="${RHEL_ACTIVATION_KEY:-}"
RHEL_ORG_ID="${RHEL_ORG_ID:-}"

if [[ -z "$RHEL_ACTIVATION_KEY" ]]; then
  echo "Reading RHEL credentials from cluster..."
  # Try dedicated Secret first
  RHEL_ACTIVATION_KEY=$(oc get secret rhel-subscription-creds -n openshift-cnv \
    -o jsonpath='{.data.activation-key}' 2>/dev/null | base64 -d 2>/dev/null || true)
  RHEL_ORG_ID=$(oc get secret rhel-subscription-creds -n openshift-cnv \
    -o jsonpath='{.data.org-id}' 2>/dev/null | base64 -d 2>/dev/null || true)
fi

if [[ -z "$RHEL_ACTIVATION_KEY" ]]; then
  # Fall back to kubevirt-ui-features ConfigMap
  RHEL_ACTIVATION_KEY=$(oc get configmap kubevirt-ui-features -n openshift-cnv \
    -o jsonpath='{.data.automaticSubscriptionActivationKey}' 2>/dev/null || true)
  RHEL_ORG_ID=$(oc get configmap kubevirt-ui-features -n openshift-cnv \
    -o jsonpath='{.data.automaticSubscriptionOrganizationId}' 2>/dev/null || true)
fi

if [[ -z "$RHEL_ACTIVATION_KEY" || -z "$RHEL_ORG_ID" ]]; then
  echo "ERROR: Could not find RHEL subscription credentials."
  echo "  Set RHEL_ACTIVATION_KEY and RHEL_ORG_ID environment variables, or"
  echo "  create Secret 'rhel-subscription-creds' in openshift-cnv namespace, or"
  echo "  configure via: Virtualization -> Settings -> Guest management"
  exit 1
fi

echo "RHEL credentials found (key: ${RHEL_ACTIVATION_KEY:0:8}...)"

# --- Apply manifests with credential substitution ---
apply_module() {
  local module_dir="$1"
  local label="$2"

  if [[ ! -d "$module_dir" ]]; then
    echo "  Skipping ${label}: ${module_dir} not found"
    return
  fi

  echo "Applying ${label}..."
  for f in "${module_dir}"/*.yaml; do
    [[ -f "$f" ]] || continue
    fname=$(basename "$f")
    # Skip kustomize config files
    [[ "$fname" == "kustomization.yaml" ]] && continue

    if grep -q "REPLACE_ACTIVATION_KEY" "$f" 2>/dev/null; then
      echo "  ${fname} (injecting credentials)"
      sed "s|REPLACE_ACTIVATION_KEY|${RHEL_ACTIVATION_KEY}|g;s|REPLACE_ORG_ID|${RHEL_ORG_ID}|g" "$f" \
        | oc apply -f - 2>&1 | grep -v "NotFound" | sed 's/^/    /' || true
    else
      echo "  ${fname}"
      oc apply -f "$f" 2>&1 | grep -v "NotFound" | sed 's/^/    /' || true
    fi
  done
}

# --- Patch IPAMClaim status with desired static IPs ---
# IPAMClaims are created without status (oc apply ignores subresources).
# We patch the status so OVN-K assigns our chosen IPs when the VM starts.
patch_ipamclaim_ip() {
  local ns="$1" claim_name="$2" ip_cidr="$3"
  oc patch ipamclaim "$claim_name" -n "$ns" \
    --type=merge --subresource=status \
    -p "{\"status\":{\"ips\":[\"${ip_cidr}\"]}}" 2>&1 | sed 's/^/    /'
}

patch_m1_ipamclaims() {
  echo "Patching Module 1 IPAMClaim IPs..."
  for ns in $(oc get namespaces -l workshop=retail-edge-ha -o name 2>/dev/null | sed 's|namespace/||'); do
    patch_ipamclaim_ip "$ns" "rhel-ha-node1.pacemaker-net" "10.101.0.20/24" || true
    patch_ipamclaim_ip "$ns" "rhel-ha-node2.pacemaker-net" "10.101.0.21/24" || true
  done
}

patch_m2_ipamclaims() {
  echo "Patching Module 2 IPAMClaim IPs..."
  for ns in $(oc get namespaces -l workshop=retail-edge-ha -o name 2>/dev/null | sed 's|namespace/||'); do
    patch_ipamclaim_ip "$ns" "microshift-gw-a.microshift-net" "10.102.0.20/24" || true
    patch_ipamclaim_ip "$ns" "microshift-gw-b.microshift-net" "10.102.0.21/24" || true
  done
}

echo ""
echo "=========================================="
echo "Applying VM Manifests"
echo "=========================================="

case "$MODULE" in
  1)
    apply_module "${MANIFESTS_DIR}/module1-rhel-ha" "Module 1: Pacemaker HA"
    patch_m1_ipamclaims
    ;;
  2)
    apply_module "${MANIFESTS_DIR}/module2-microshift" "Module 2: MicroShift"
    patch_m2_ipamclaims
    ;;
  3)
    apply_module "${MANIFESTS_DIR}/module3-twonode" "Module 3: Two-Node OpenShift"
    ;;
  all)
    apply_module "${MANIFESTS_DIR}/module1-rhel-ha" "Module 1: Pacemaker HA"
    patch_m1_ipamclaims
    apply_module "${MANIFESTS_DIR}/module2-microshift" "Module 2: MicroShift"
    patch_m2_ipamclaims
    apply_module "${MANIFESTS_DIR}/module3-twonode" "Module 3: Two-Node OpenShift"
    ;;
  *)
    echo "Usage: $0 [1|2|3|all]"
    exit 1
    ;;
esac

echo ""
echo "Done. Credentials were injected at apply time only — never written to disk."
