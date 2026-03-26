#!/bin/bash
# =============================================================================
# Post-Deployment Validation Script
# =============================================================================
# Validates that the Retail Edge HA Workshop deployment is complete and ready
# for students to use. Checks all components across sync waves 0-4.
#
# Usage:
#   ./scripts/validate-workshop-deployment.sh [student-count]
#
# Exit codes:
#   0 - All validations passed, workshop ready
#   1 - Validation failures found, workshop not ready
#   2 - Script error (missing tools, cluster access, etc.)
# =============================================================================

# Disable strict error handling to allow all validations to run
# set -eo pipefail

# Configuration
EXPECTED_STUDENTS="${1:-5}"
WORKSHOP_NAME="retail-edge-ha"
GITOPS_NAMESPACE="retail-edge-ha-gitops"
ARGOCD_NAMESPACE="openshift-gitops"
CNV_NAMESPACE="openshift-cnv"
STORAGE_CLASS="ocs-external-storagecluster-ceph-rbd"
MIN_OPENSHIFT_VERSION="4.21"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
PASSED=0
FAILED=0
WARNINGS=0

# Helper functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_section() {
    echo -e "\n${BLUE}### $1${NC}"
}

check_pass() {
    echo -e "${GREEN}✅ $1${NC}"
    ((PASSED++))
}

check_fail() {
    echo -e "${RED}❌ $1${NC}"
    ((FAILED++))
}

check_warn() {
    echo -e "${YELLOW}⚠️  $1${NC}"
    ((WARNINGS++))
}

check_info() {
    echo -e "ℹ️  $1"
}

# Validation functions
validate_prerequisites() {
    print_section "Prerequisites"

    # Check oc command
    if command -v oc &>/dev/null; then
        check_pass "oc CLI installed"
    else
        check_fail "oc CLI not found"
        return 1
    fi

    # Check cluster access
    if oc whoami &>/dev/null; then
        local user=$(oc whoami)
        check_pass "Cluster access (logged in as: $user)"
    else
        check_fail "No cluster access - run 'oc login' first"
        return 1
    fi

    # Check OpenShift version
    local ocp_version=$(oc version -o json 2>/dev/null | jq -r '.openshiftVersion // .serverVersion.gitVersion' | sed 's/v//')
    local major_minor=$(echo "$ocp_version" | cut -d. -f1,2)

    # Version comparison without bc (bash-native)
    local min_major=$(echo "$MIN_OPENSHIFT_VERSION" | cut -d. -f1)
    local min_minor=$(echo "$MIN_OPENSHIFT_VERSION" | cut -d. -f2)
    local curr_major=$(echo "$major_minor" | cut -d. -f1)
    local curr_minor=$(echo "$major_minor" | cut -d. -f2)

    if [[ $curr_major -gt $min_major ]] || [[ $curr_major -eq $min_major && $curr_minor -ge $min_minor ]]; then
        check_pass "OpenShift version: $ocp_version (>= $MIN_OPENSHIFT_VERSION)"
    else
        check_fail "OpenShift version: $ocp_version (requires >= $MIN_OPENSHIFT_VERSION)"
    fi

    # Check OpenShift Virtualization operator
    if oc get csv -n "$CNV_NAMESPACE" 2>/dev/null | grep -i "kubevirt" | grep -q "Succeeded"; then
        local cnv_version=$(oc get csv -n "$CNV_NAMESPACE" -o json 2>/dev/null | jq -r '.items[] | select(.metadata.name | contains("kubevirt")) | .spec.version')
        check_pass "OpenShift Virtualization operator installed: $cnv_version"
    else
        check_warn "OpenShift Virtualization operator not found or not ready (check: oc get csv -n $CNV_NAMESPACE)"
    fi

    # Check storage class
    if oc get storageclass "$STORAGE_CLASS" &>/dev/null; then
        check_pass "Storage class exists: $STORAGE_CLASS"
    else
        check_fail "Storage class not found: $STORAGE_CLASS"
    fi
}

validate_helm_release() {
    print_section "Helm Release"

    if command -v helm &>/dev/null; then
        if helm list -n "$GITOPS_NAMESPACE" 2>/dev/null | grep -q "$WORKSHOP_NAME"; then
            local revision=$(helm list -n "$GITOPS_NAMESPACE" -o json | jq -r --arg name "$WORKSHOP_NAME" '.[] | select(.name==$name) | .revision')
            local status=$(helm list -n "$GITOPS_NAMESPACE" -o json | jq -r --arg name "$WORKSHOP_NAME" '.[] | select(.name==$name) | .status')

            if [[ "$status" == "deployed" ]]; then
                check_pass "Helm release deployed: $WORKSHOP_NAME (revision $revision)"
            else
                check_fail "Helm release status: $status (expected: deployed)"
            fi
        else
            check_fail "Helm release not found: $WORKSHOP_NAME"
        fi
    else
        check_warn "Helm not installed - skipping Helm validation"
    fi
}

validate_argocd_applications() {
    print_section "ArgoCD Applications"

    # Count applications
    local total=$(oc get applications -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | grep -c "$WORKSHOP_NAME" || true)

    if [[ -z "$total" || "$total" == "0" ]]; then
        check_fail "No ArgoCD applications found for workshop"
        return 0  # Continue validation
    fi

    # Count synced and healthy
    local synced=$(oc get applications -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | \
        grep "$WORKSHOP_NAME" | awk '{print $2}' | grep -c "Synced" || true)

    local healthy=$(oc get applications -n "$ARGOCD_NAMESPACE" --no-headers 2>/dev/null | \
        grep "$WORKSHOP_NAME" | awk '{print $3}' | grep -c "Healthy" || true)

    # Show summary first (avoid while loop issues)
    check_info "Found $total ArgoCD applications ($synced synced, $healthy healthy)"

    # Summary
    if [[ $synced -ge 7 && $healthy -ge 7 ]]; then
        check_pass "ArgoCD applications ready: $synced/$total synced, $healthy/$total healthy"
    else
        check_warn "ArgoCD applications: $synced/$total synced, $healthy/$total healthy (expected >= 7)"
    fi
}

validate_namespaces() {
    print_section "Namespaces"

    # Expected namespaces: students * 2 (workload + UDN) + showroom * students + infrastructure + gitops
    local expected_total=$((EXPECTED_STUDENTS * 2 + EXPECTED_STUDENTS + 2))

    # Count retail-edge namespaces
    local retail_count=$(oc get namespaces --no-headers 2>/dev/null | grep -c "^retail-edge-" || echo "0")

    # Count showroom namespaces
    local showroom_count=$(oc get namespaces --no-headers 2>/dev/null | grep -c "^showroom-student-" || echo "0")

    local total_count=$((retail_count + showroom_count))

    if [[ $total_count -ge $expected_total ]]; then
        check_pass "Namespaces created: $total_count (expected: $expected_total)"
        check_info "  Retail-edge: $retail_count namespaces"
        check_info "  Showroom: $showroom_count namespaces"
    else
        check_fail "Namespaces created: $total_count (expected: $expected_total)"
    fi

    # Check resource quotas
    local quota_count=$(oc get resourcequota -A 2>/dev/null | grep -c "retail-edge-student" || echo "0")
    if [[ $quota_count -ge $EXPECTED_STUDENTS ]]; then
        check_pass "Resource quotas applied: $quota_count (expected: $EXPECTED_STUDENTS)"
    else
        check_fail "Resource quotas applied: $quota_count (expected: $EXPECTED_STUDENTS)"
    fi
}

validate_networking() {
    print_section "Networking (User Defined Networks)"

    # Expected UDNs: 3 modules * students
    local expected_udns=$((3 * EXPECTED_STUDENTS))

    local udn_count=$(oc get userdefinednetworks -A 2>/dev/null | grep -c "retail-edge" || echo "0")

    if [[ $udn_count -ge $expected_udns ]]; then
        check_pass "User Defined Networks: $udn_count (expected: $expected_udns)"
    else
        check_fail "User Defined Networks: $udn_count (expected: $expected_udns)"
    fi

    # Sample check for student-01
    if oc get userdefinednetwork pacemaker-net -n retail-edge-student-01-udn &>/dev/null; then
        check_pass "Sample UDN exists: pacemaker-net (student-01)"
    else
        check_fail "Sample UDN missing: pacemaker-net (student-01)"
    fi
}

validate_virtualmachines() {
    print_section "VirtualMachines"

    # Count total VMs (7 per student: 2 module1 + 2 module2 + 3 module3)
    local vm_count=$(oc get virtualmachines -A 2>/dev/null | grep -c "retail-edge-student" || echo "0")
    local expected_vms=$((7 * EXPECTED_STUDENTS))

    if [[ $vm_count -ge $expected_vms ]]; then
        check_pass "VirtualMachines created: $vm_count (expected: $expected_vms)"
    else
        check_warn "VirtualMachines created: $vm_count (expected: $expected_vms for all modules)"
    fi

    # Check VM status for student-01
    local stopped_vms=$(oc get vms -n retail-edge-student-01 2>/dev/null | grep -c "Stopped" || echo "0")
    if [[ $stopped_vms -gt 0 ]]; then
        check_pass "VMs in stopped state: $stopped_vms (auto-start disabled)"
    fi

    # Check DataVolume status
    local dv_count=$(oc get datavolumes -A 2>/dev/null | grep -c "retail-edge-student" || echo "0")
    if [[ $dv_count -gt 0 ]]; then
        check_info "DataVolumes: $dv_count total"

        # Check provisioning status
        local succeeded=$(oc get datavolumes -A 2>/dev/null | grep "retail-edge" | grep -c "Succeeded" || true)
        local importing=$(oc get datavolumes -A 2>/dev/null | grep "retail-edge" | grep -c "ImportInProgress" || true)
        local pending=$(oc get datavolumes -A 2>/dev/null | grep "retail-edge" | grep -c "PendingPopulation" || true)

        if [[ ! -z "$succeeded" && "$succeeded" -gt 0 ]]; then
            check_pass "DataVolumes ready: $succeeded"
        fi

        if [[ $importing -gt 0 ]]; then
            check_warn "DataVolumes importing: $importing (wait for completion)"
        fi

        if [[ $pending -gt 0 ]]; then
            check_warn "DataVolumes pending: $pending (will start when VM starts)"
        fi
    else
        check_fail "No DataVolumes found"
    fi
}

validate_showroom() {
    print_section "Showroom Lab Environment"

    # Check Showroom namespaces
    local showroom_ns_count=$(oc get namespaces --no-headers 2>/dev/null | grep -c "^showroom-student-" || echo "0")
    if [[ $showroom_ns_count -ge $EXPECTED_STUDENTS ]]; then
        check_pass "Showroom namespaces: $showroom_ns_count (expected: $EXPECTED_STUDENTS)"
    else
        check_fail "Showroom namespaces: $showroom_ns_count (expected: $EXPECTED_STUDENTS)"
    fi

    # Check Showroom pods for student-01
    if oc get namespace showroom-student-01 &>/dev/null; then
        local pod_count=$(oc get pods -n showroom-student-01 --no-headers 2>/dev/null | wc -l)
        local ready_pods=$(oc get pods -n showroom-student-01 --no-headers 2>/dev/null | grep "Running" | wc -l)

        if [[ $ready_pods -ge 4 ]]; then
            check_pass "Showroom pods (student-01): $ready_pods/4 running"
        else
            check_fail "Showroom pods (student-01): $ready_pods/4 running (expected: 4)"
        fi

        # Check ConfigMap
        if oc get configmap student-env -n showroom-student-01 &>/dev/null; then
            check_pass "Student environment ConfigMap exists (student-01)"
        else
            check_fail "Student environment ConfigMap missing (student-01)"
        fi

        # Check if terminal is patched with env vars
        local has_envfrom=$(oc get deployment showroom-terminal -n showroom-student-01 -o json 2>/dev/null | \
            jq -r '.spec.template.spec.containers[0].envFrom[]?.configMapRef.name // empty')

        if [[ "$has_envfrom" == "student-env" ]]; then
            check_pass "Showroom terminal patched with environment variables"
        else
            check_warn "Showroom terminal not patched - run: ./scripts/patch-showroom-terminals.sh $EXPECTED_STUDENTS"
        fi

        # Check Showroom route
        if oc get route -n showroom-student-01 &>/dev/null 2>&1; then
            local showroom_url="https://$(oc get route -n showroom-student-01 -o jsonpath='{.items[0].spec.host}' 2>/dev/null)"
            check_pass "Showroom URL accessible: $showroom_url"
        else
            check_fail "Showroom route not found (student-01)"
        fi
    else
        check_fail "Showroom namespace not found: showroom-student-01"
    fi
}

generate_summary() {
    print_header "Validation Summary"

    local total=$((PASSED + FAILED + WARNINGS))

    echo -e "${GREEN}Passed:   $PASSED${NC}"
    echo -e "${YELLOW}Warnings: $WARNINGS${NC}"
    echo -e "${RED}Failed:   $FAILED${NC}"
    echo "Total:    $total"
    echo ""

    # Determine readiness
    if [[ $FAILED -eq 0 ]]; then
        if [[ $WARNINGS -eq 0 ]]; then
            echo -e "${GREEN}✅ Workshop is READY for students!${NC}"
            echo ""
            echo "Next steps:"
            echo "  1. Share Showroom URLs with students"
            echo "  2. Students will start VMs when needed during labs"
            echo "  3. Monitor with: oc get vms -A | grep retail-edge"
            return 0
        else
            echo -e "${YELLOW}⚠️  Workshop is MOSTLY READY but has warnings${NC}"
            echo ""
            echo "Recommendations:"
            echo "  - Review warnings above"
            echo "  - DataVolumes may still be importing (wait 5-10 minutes)"
            echo "  - Run patch script if terminals not configured"
            echo "  - Test with one student before full deployment"
            return 0
        fi
    else
        echo -e "${RED}❌ Workshop is NOT READY${NC}"
        echo ""
        echo "Action required:"
        echo "  1. Review failed checks above"
        echo "  2. Check ArgoCD application status: oc get applications -n $ARGOCD_NAMESPACE"
        echo "  3. Check pod logs for errors"
        echo "  4. Re-run validation after fixing issues"
        return 1
    fi
}

# Main execution
main() {
    print_header "Retail Edge HA Workshop - Post-Deployment Validation"
    echo "Expected students: $EXPECTED_STUDENTS"
    echo "Workshop name: $WORKSHOP_NAME"
    echo "Timestamp: $(date)"

    # Run all validations
    validate_prerequisites || exit 2
    validate_helm_release
    validate_argocd_applications
    validate_namespaces
    validate_networking
    validate_virtualmachines
    validate_showroom

    # Generate summary and exit with appropriate code
    generate_summary
    exit $?
}

# Run main function
main "$@"
