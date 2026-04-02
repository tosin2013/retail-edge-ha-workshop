#!/bin/bash
# =============================================================================
# Pre-Deployment Validation Script
# Checks all prerequisites before deploying the Retail Edge HA Workshop
# =============================================================================

set -o pipefail

echo "=========================================="
echo "Retail Edge HA Workshop - Pre-Deployment Check"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

# Function to check command status
check() {
  if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} $1"
  else
    echo -e "${RED}✗${NC} $1"
    ERRORS=$((ERRORS + 1))
  fi
}

warn() {
  echo -e "${YELLOW}⚠${NC} $1"
  WARNINGS=$((WARNINGS + 1))
}

info() {
  echo -e "  $1"
}

# =============================================================================
# 1. Cluster Connection
# =============================================================================
echo "1. Checking cluster connection..."
oc whoami &>/dev/null
check "Connected to cluster as $(oc whoami 2>/dev/null)"

oc cluster-info &>/dev/null
check "Cluster API reachable"

CLUSTER_DOMAIN=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}' 2>/dev/null)
info "Cluster domain: ${CLUSTER_DOMAIN}"

API_URL=$(oc whoami --show-server 2>/dev/null)
info "API URL: ${API_URL}"
echo ""

# =============================================================================
# 2. OpenShift Version
# =============================================================================
echo "2. Checking OpenShift version..."
OCP_VERSION=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null)
MAJOR=$(echo $OCP_VERSION | cut -d'.' -f1)
MINOR=$(echo $OCP_VERSION | cut -d'.' -f2)

if [ "$MAJOR" -gt 4 ] || ([ "$MAJOR" -eq 4 ] && [ "$MINOR" -ge 21 ]); then
  check "OpenShift version ${OCP_VERSION} (requires 4.21+)"
else
  echo -e "${RED}✗${NC} OpenShift version ${OCP_VERSION} is too old (requires 4.21+)"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# =============================================================================
# 3. Node Resources
# =============================================================================
echo "3. Checking node resources..."
NODE_COUNT=$(oc get nodes --no-headers 2>/dev/null | wc -l)
check "${NODE_COUNT} nodes available"

TOTAL_CPU=$(oc get nodes -o json 2>/dev/null | jq '[.items[].status.capacity.cpu | tonumber] | add' 2>/dev/null || echo "0")
TOTAL_MEM_KB=$(oc get nodes -o json 2>/dev/null | jq '[.items[].status.capacity.memory | rtrimstr("Ki") | tonumber] | add' 2>/dev/null || echo "0")
TOTAL_MEM_GB=$((TOTAL_MEM_KB / 1024 / 1024))

info "Total cluster capacity: ${TOTAL_CPU} CPU, ${TOTAL_MEM_GB} GiB RAM"

# Calculate required resources (for 2 students with all modules)
NUM_STUDENTS=2
REQUIRED_CPU=$((NUM_STUDENTS * 17))  # 17 CPU per student (2+2+2+2 for modules 1-2, 4+4+1 for module 3)
REQUIRED_MEM_GB=$((NUM_STUDENTS * 50))  # 50 GiB per student (4+4+4+4 for modules 1-2, 16+16+2 for module 3)

if [[ ${TOTAL_CPU} -ge ${REQUIRED_CPU} ]] && [[ ${TOTAL_MEM_GB} -ge ${REQUIRED_MEM_GB} ]]; then
  check "Sufficient resources for ${NUM_STUDENTS} students (all modules)"
  info "Required: ${REQUIRED_CPU} CPU, ${REQUIRED_MEM_GB} GiB | Available: ${TOTAL_CPU} CPU, ${TOTAL_MEM_GB} GiB"
  info "14 VMs will be deployed (7 per student)"
else
  warn "Limited resources - may not support ${NUM_STUDENTS} students with all modules"
  info "Required: ${REQUIRED_CPU} CPU, ${REQUIRED_MEM_GB} GiB | Available: ${TOTAL_CPU} CPU, ${TOTAL_MEM_GB} GiB"
fi
echo ""

# =============================================================================
# 4. Storage Classes
# =============================================================================
echo "4. Checking storage classes..."
STORAGE_CLASSES=$(oc get storageclass --no-headers 2>/dev/null | wc -l)
if [ $STORAGE_CLASSES -gt 0 ]; then
  check "${STORAGE_CLASSES} storage class(es) available"

  DEFAULT_SC=$(oc get storageclass -o json 2>/dev/null | jq -r '.items[] | select(.metadata.annotations."storageclass.kubernetes.io/is-default-class" == "true") | .metadata.name' | head -1)
  if [ -n "$DEFAULT_SC" ]; then
    info "Default storage class: ${DEFAULT_SC}"
  fi

  RBD_SC=$(oc get storageclass -o json 2>/dev/null | jq -r '.items[] | select(.metadata.name | contains("rbd")) | .metadata.name' | head -1)
  if [ -n "$RBD_SC" ]; then
    info "RBD storage class: ${RBD_SC} (preferred for VMs)"
  fi
else
  echo -e "${RED}✗${NC} No storage classes found"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# =============================================================================
# 5. OpenShift GitOps (ArgoCD)
# =============================================================================
echo "5. Checking OpenShift GitOps operator..."
GITOPS_NS=$(oc get namespace openshift-gitops 2>/dev/null)
if [ $? -eq 0 ]; then
  check "openshift-gitops namespace exists"

  GITOPS_CSV=$(oc get csv -n openshift-gitops 2>/dev/null | grep -i gitops | awk '{print $1}' | head -1)
  if [ -n "$GITOPS_CSV" ]; then
    GITOPS_STATUS=$(oc get csv -n openshift-gitops "$GITOPS_CSV" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$GITOPS_STATUS" = "Succeeded" ]; then
      check "OpenShift GitOps operator ready (${GITOPS_CSV})"
    else
      warn "OpenShift GitOps operator status: ${GITOPS_STATUS}"
    fi
  else
    warn "OpenShift GitOps operator not found - will need to be installed"
    info "Install with: oc create -f https://raw.githubusercontent.com/redhat-developer/gitops-operator/master/config/samples/gitops_v1alpha1_gitopsservice.yaml"
  fi
else
  warn "OpenShift GitOps not installed - ArgoCD required for workshop"
  info "The workshop expects ArgoCD to be available in openshift-gitops namespace"
  info "Install OpenShift GitOps operator from OperatorHub before deploying"
fi
echo ""

# =============================================================================
# 6. OpenShift Virtualization
# =============================================================================
echo "6. Checking OpenShift Virtualization operator..."
CNV_NS=$(oc get namespace openshift-cnv 2>/dev/null)
if [ $? -eq 0 ]; then
  check "openshift-cnv namespace exists"

  CNV_CSV=$(oc get csv -n openshift-cnv 2>/dev/null | grep -i kubevirt | awk '{print $1}' | head -1)
  if [ -n "$CNV_CSV" ]; then
    CNV_STATUS=$(oc get csv -n openshift-cnv "$CNV_CSV" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$CNV_STATUS" = "Succeeded" ]; then
      check "OpenShift Virtualization operator ready (${CNV_CSV})"

      # Check HyperConverged
      HCO=$(oc get hyperconverged -n openshift-cnv kubevirt-hyperconverged -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
      if [ "$HCO" = "True" ]; then
        check "HyperConverged instance available"
      else
        warn "HyperConverged instance not available yet"
      fi
    else
      warn "OpenShift Virtualization operator status: ${CNV_STATUS}"
    fi
  else
    warn "OpenShift Virtualization operator not found"
    info "Will be auto-installed via AgnosticD workload (ocp4_workload_retail_edge_ha_auto_install_virtualization=true)"
  fi
else
  warn "OpenShift Virtualization not installed"
  info "Will be auto-installed via AgnosticD workload (ocp4_workload_retail_edge_ha_auto_install_virtualization=true)"
fi
echo ""

# =============================================================================
# 7. Network Configuration
# =============================================================================
echo "7. Checking network configuration..."
CNI=$(oc get network.config.openshift.io cluster -o jsonpath='{.spec.networkType}' 2>/dev/null)
if [ "$CNI" = "OVNKubernetes" ]; then
  check "OVN-Kubernetes CNI (supports User Defined Networks)"
else
  echo -e "${RED}✗${NC} CNI is ${CNI} (requires OVN-Kubernetes for UDN support)"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# =============================================================================
# 8. RHACM / Edge Manager
# =============================================================================
echo "8. Checking RHACM and Edge Manager readiness..."
ACM_NS=$(oc get namespace open-cluster-management 2>/dev/null)
if [ $? -eq 0 ]; then
  check "open-cluster-management namespace exists"

  ACM_CSV=$(oc get csv -n open-cluster-management 2>/dev/null | grep -i "advanced-cluster-management" | awk '{print $1}' | head -1)
  if [ -n "$ACM_CSV" ]; then
    ACM_STATUS=$(oc get csv -n open-cluster-management "$ACM_CSV" -o jsonpath='{.status.phase}' 2>/dev/null)
    if [ "$ACM_STATUS" = "Succeeded" ]; then
      check "RHACM operator ready (${ACM_CSV})"
    else
      warn "RHACM operator status: ${ACM_STATUS}"
    fi
  else
    warn "RHACM operator not found - will be installed by workshop deployment"
  fi

  MCH_STATUS=$(oc get multiclusterhub -n open-cluster-management -o jsonpath='{.items[0].status.phase}' 2>/dev/null)
  if [ "$MCH_STATUS" = "Running" ]; then
    check "MultiClusterHub running"

    EM_NS=$(oc get namespace redhat-edge-manager 2>/dev/null)
    if [ $? -eq 0 ]; then
      EM_PODS=$(oc get pods -n redhat-edge-manager --no-headers 2>/dev/null | grep -c "Running" || echo "0")
      if [ "$EM_PODS" -gt 0 ]; then
        check "Edge Manager running ($EM_PODS pods in redhat-edge-manager)"
      else
        warn "Edge Manager namespace exists but no running pods"
      fi
    else
      info "Edge Manager not yet deployed - workshop will deploy it via ArgoCD"
    fi
  else
    info "MultiClusterHub not running yet (status: ${MCH_STATUS:-not found})"
  fi
else
  warn "RHACM not installed - workshop deployment will install it"
fi
echo ""

# =============================================================================
# 9. RBAC Permissions
# =============================================================================
echo "9. Checking permissions..."
oc auth can-i create namespace &>/dev/null
check "Can create namespaces"

oc auth can-i create application -n openshift-gitops &>/dev/null
check "Can create ArgoCD applications"

oc auth can-i create virtualmachine -n default &>/dev/null
check "Can create VirtualMachines"
echo ""

# =============================================================================
# 10. AgnosticD Setup
# =============================================================================
echo "10. Checking AgnosticD v2 setup..."
if [ -d "/home/vpcuser/agnosticd-v2" ]; then
  check "AgnosticD v2 directory exists"

  if [ -f "/home/vpcuser/agnosticd-v2/bin/agd" ]; then
    check "agd command available"
  fi

  if [ -d "/home/vpcuser/agnosticd-v2/ansible/roles/ocp4_workload_retail_edge_ha" ]; then
    check "retail-edge-ha workload role installed"
  else
    echo -e "${RED}✗${NC} retail-edge-ha workload role not found"
    ERRORS=$((ERRORS + 1))
  fi

  if [ -f "/home/vpcuser/agnosticd-v2-vars/retail-edge-ha-workload.yml" ]; then
    check "Configuration file exists"
  else
    warn "Configuration file not found: /home/vpcuser/agnosticd-v2-vars/retail-edge-ha-workload.yml"
  fi
else
  echo -e "${RED}✗${NC} AgnosticD v2 not found at /home/vpcuser/agnosticd-v2"
  ERRORS=$((ERRORS + 1))
fi
echo ""

# =============================================================================
# Summary
# =============================================================================
echo "=========================================="
echo "Summary"
echo "=========================================="

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
  echo -e "${GREEN}✓ All checks passed!${NC}"
  echo ""
  echo "Ready to deploy:"
  echo "  cd /home/vpcuser/agnosticd-v2"
  echo "  ./bin/agd provision --guid workshop-test --config retail-edge-ha-workload --account existing-cluster"
  exit 0
elif [ $ERRORS -eq 0 ]; then
  echo -e "${YELLOW}⚠ ${WARNINGS} warning(s) found${NC}"
  echo "You can proceed with deployment, but review warnings above."
  echo ""
  echo "To deploy:"
  echo "  cd /home/vpcuser/agnosticd-v2"
  echo "  ./bin/agd provision --guid workshop-test --config retail-edge-ha-workload --account existing-cluster"
  exit 0
else
  echo -e "${RED}✗ ${ERRORS} error(s) and ${WARNINGS} warning(s) found${NC}"
  echo "Please fix errors before deploying."
  exit 1
fi
