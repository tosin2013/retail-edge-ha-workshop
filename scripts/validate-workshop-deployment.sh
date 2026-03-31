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
OUTPUT_FORMAT="${OUTPUT_FORMAT:-text}"  # Options: text, json, both
OUTPUT_FILE="${OUTPUT_FILE:-/tmp/validation-report.json}"

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
    local retail_count=$(oc get namespaces --no-headers 2>/dev/null | grep "^retail-edge-" | wc -l || echo "0")
    retail_count=${retail_count:-0}

    # Count showroom namespaces
    local showroom_count=$(oc get namespaces --no-headers 2>/dev/null | grep "^showroom-student-" | wc -l || echo "0")
    showroom_count=${showroom_count:-0}

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

validate_fleet_management() {
    print_section "Fleet Management (RHACM)"

    # Check if fleet management is enabled (namespace exists)
    if ! oc get namespace open-cluster-management &>/dev/null; then
        check_info "Fleet management not enabled (open-cluster-management namespace not found)"
        return 0  # Not a failure, just optional
    fi

    # Check RHACM operator
    if oc get csv -n open-cluster-management 2>/dev/null | grep -i "advanced-cluster-management" | grep -q "Succeeded"; then
        local acm_version=$(oc get csv -n open-cluster-management -o json 2>/dev/null | jq -r '.items[] | select(.metadata.name | contains("advanced-cluster-management")) | .spec.version')
        check_pass "RHACM operator installed: $acm_version"
    else
        check_fail "RHACM operator not found or not ready"
        return 0
    fi

    # Check MultiClusterHub status
    if oc get multiclusterhub -n open-cluster-management &>/dev/null; then
        local hub_status=$(oc get multiclusterhub -n open-cluster-management -o json 2>/dev/null | jq -r '.items[0].status.phase // "Unknown"')
        if [[ "$hub_status" == "Running" ]]; then
            check_pass "MultiClusterHub status: Running"
        else
            check_fail "MultiClusterHub status: $hub_status (expected: Running)"
        fi
    else
        check_fail "MultiClusterHub not found"
    fi

    # Check ManagedCluster CRs (one per student)
    local managed_cluster_count=$(oc get managedcluster 2>/dev/null | grep -c "retail-edge-student" || echo "0")
    if [[ $managed_cluster_count -ge $EXPECTED_STUDENTS ]]; then
        check_pass "ManagedClusters created: $managed_cluster_count (expected: $EXPECTED_STUDENTS)"
    else
        check_warn "ManagedClusters created: $managed_cluster_count (expected: $EXPECTED_STUDENTS)"
    fi

    # Check ManagedCluster availability (sample student-01)
    if oc get managedcluster retail-edge-student-01 &>/dev/null 2>&1; then
        local cluster_available=$(oc get managedcluster retail-edge-student-01 -o json 2>/dev/null | \
            jq -r '.status.conditions[] | select(.type=="ManagedClusterConditionAvailable") | .status')
        if [[ "$cluster_available" == "True" ]]; then
            check_pass "ManagedCluster available: retail-edge-student-01"
        else
            check_warn "ManagedCluster not available: retail-edge-student-01"
        fi
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

generate_json_output() {
    # Generate JSON report for RHDP catalog integration
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local status="HEALTHY"

    if [[ $FAILED -gt 0 ]]; then
        status="FAILED"
    elif [[ $WARNINGS -gt 0 ]]; then
        status="DEGRADED"
    fi

    # Pre-compute all values to avoid escaping issues in heredoc
    local argocd_total=$(oc get applications -n $ARGOCD_NAMESPACE --no-headers 2>/dev/null | grep "$WORKSHOP_NAME" | wc -l || echo "0")
    local argocd_synced=$(oc get applications -n $ARGOCD_NAMESPACE --no-headers 2>/dev/null | grep "$WORKSHOP_NAME" | awk '{print $2}' | grep "Synced" | wc -l || echo "0")
    local argocd_healthy=$(oc get applications -n $ARGOCD_NAMESPACE --no-headers 2>/dev/null | grep "$WORKSHOP_NAME" | awk '{print $3}' | grep "Healthy" | wc -l || echo "0")

    local ns_student=$(oc get namespaces --no-headers 2>/dev/null | grep "^retail-edge-student-" | wc -l || echo "0")
    local ns_showroom=$(oc get namespaces --no-headers 2>/dev/null | grep "^showroom-student-" | wc -l || echo "0")
    local ns_quotas=$(oc get resourcequota -A 2>/dev/null | grep "retail-edge-student" | wc -l || echo "0")

    local vm_total=$(oc get virtualmachines -A 2>/dev/null | grep "retail-edge-student" | wc -l || echo "0")
    local dv_ready=$(oc get datavolumes -A 2>/dev/null | grep "retail-edge" | grep "Succeeded" | wc -l || echo "0")

    local showroom_pods=$(oc get pods -n showroom-student-01 --no-headers 2>/dev/null | grep "Running" | wc -l || echo "0")
    local showroom_url=$(oc get route -n showroom-student-01 -o jsonpath='{.items[0].spec.host}' 2>/dev/null || echo "not-found")

    # Trim whitespace
    argocd_total=$(echo "$argocd_total" | tr -d ' \n')
    argocd_synced=$(echo "$argocd_synced" | tr -d ' \n')
    argocd_healthy=$(echo "$argocd_healthy" | tr -d ' \n')
    ns_student=$(echo "$ns_student" | tr -d ' \n')
    ns_showroom=$(echo "$ns_showroom" | tr -d ' \n')
    ns_quotas=$(echo "$ns_quotas" | tr -d ' \n')
    vm_total=$(echo "$vm_total" | tr -d ' \n')
    dv_ready=$(echo "$dv_ready" | tr -d ' \n')
    showroom_pods=$(echo "$showroom_pods" | tr -d ' \n')

    local status_message
    if [[ $status == "HEALTHY" ]]; then
        status_message="Workshop is ready for students"
    elif [[ $status == "DEGRADED" ]]; then
        status_message="Workshop has warnings but is mostly ready"
    else
        status_message="Workshop is not ready - review failed checks"
    fi

    cat > "$OUTPUT_FILE" <<EOF
{
  "validation_timestamp": "$timestamp",
  "validation_status": "$status",
  "expected_students": $EXPECTED_STUDENTS,
  "summary": {
    "total_checks": $((PASSED + FAILED + WARNINGS)),
    "passed": $PASSED,
    "warnings": $WARNINGS,
    "failed": $FAILED
  },
  "components": {
    "argocd_applications": {
      "total": $argocd_total,
      "synced": $argocd_synced,
      "healthy": $argocd_healthy
    },
    "namespaces": {
      "student_namespaces": $ns_student,
      "showroom_namespaces": $ns_showroom,
      "resource_quotas": $ns_quotas
    },
    "virtualmachines": {
      "total": $vm_total,
      "datavolumes_succeeded": $dv_ready
    },
    "showroom": {
      "running_pods": $showroom_pods,
      "sample_url": "https://$showroom_url"
    }
  },
  "status_message": "$status_message"
}
EOF

    if [[ "$OUTPUT_FORMAT" == "json" ]] || [[ "$OUTPUT_FORMAT" == "both" ]]; then
        echo -e "${BLUE}JSON report saved to: $OUTPUT_FILE${NC}"
        cat "$OUTPUT_FILE"
    fi
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--students)
                EXPECTED_STUDENTS="$2"
                shift 2
                ;;
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS] [STUDENT_COUNT]"
                echo ""
                echo "Options:"
                echo "  -s, --students NUM    Expected number of students (default: 5)"
                echo "  -f, --format FORMAT   Output format: text, json, both (default: text)"
                echo "  -o, --output FILE     JSON output file (default: /tmp/validation-report.json)"
                echo "  -h, --help            Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0 10                                    # Validate for 10 students"
                echo "  $0 --students 25 --format json           # JSON output for 25 students"
                echo "  $0 -s 5 -f both -o report.json           # Both text and JSON output"
                exit 0
                ;;
            *)
                # Positional argument (student count)
                EXPECTED_STUDENTS="$1"
                shift
                ;;
        esac
    done
}

# Main execution
main() {
    parse_arguments "$@"

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
    validate_fleet_management

    # Generate summary and exit with appropriate code
    generate_summary

    # Generate JSON output if requested
    if [[ "$OUTPUT_FORMAT" == "json" ]] || [[ "$OUTPUT_FORMAT" == "both" ]]; then
        generate_json_output
    fi

    exit $?
}

# Run main function
main "$@"
