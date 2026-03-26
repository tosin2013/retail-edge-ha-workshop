#!/bin/bash
# =============================================================================
# Chaos GameDay Script - Automated Failure Injection
# =============================================================================
# This script simulates a retail edge chaos engineering "GameDay" by randomly
# injecting failures into the workshop VMs. Use this to validate resilience
# and practice incident response.
#
# Usage:
#   ./scripts/chaos-gameday.sh <namespace> <duration_minutes> [failure_rate]
#
# Examples:
#   # Run 15-minute GameDay with default failure rate (every 3-5 minutes)
#   ./scripts/chaos-gameday.sh retail-edge-student-01 15
#
#   # Run 60-minute GameDay with high failure rate (every 1-2 minutes)
#   ./scripts/chaos-gameday.sh retail-edge-student-01 60 high
#
# Failure Scenarios:
#   - Random VM stop (hardware failure simulation)
#   - Network partition (firewall rule injection)
#   - CPU saturation (stress-ng workload)
#   - Process crash (kill critical service)
#   - Disk pressure (fill /tmp with garbage)
#
# Prerequisites:
#   - oc CLI logged in to cluster
#   - virtctl installed
#   - Student namespace exists
# =============================================================================

set -e

# Configuration
NAMESPACE="${1:-retail-edge-student-01}"
DURATION_MINUTES="${2:-15}"
FAILURE_RATE="${3:-medium}"

# Failure rate intervals (seconds)
case "${FAILURE_RATE}" in
    low)
        MIN_INTERVAL=300  # 5 minutes
        MAX_INTERVAL=600  # 10 minutes
        ;;
    medium)
        MIN_INTERVAL=180  # 3 minutes
        MAX_INTERVAL=300  # 5 minutes
        ;;
    high)
        MIN_INTERVAL=60   # 1 minute
        MAX_INTERVAL=120  # 2 minutes
        ;;
    *)
        echo "ERROR: Invalid failure rate. Use: low, medium, high"
        exit 1
        ;;
esac

# VM list
VMS=(
    "rhel-ha-node1"
    "rhel-ha-node2"
    "microshift-gw-a"
    "microshift-gw-b"
    "twonode-master1"
    "twonode-master2"
)

# Chaos scenarios
SCENARIOS=(
    "vm_stop"
    "network_partition"
    "cpu_saturation"
    "process_crash"
)

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging
LOG_FILE="/tmp/chaos-gameday-${NAMESPACE}-$(date +%Y%m%d-%H%M%S).log"

log() {
    local level="$1"
    shift
    local message="$@"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "${level}" in
        INFO)
            echo -e "${GREEN}[${timestamp}] [INFO]${NC} ${message}" | tee -a "${LOG_FILE}"
            ;;
        WARN)
            echo -e "${YELLOW}[${timestamp}] [WARN]${NC} ${message}" | tee -a "${LOG_FILE}"
            ;;
        ERROR)
            echo -e "${RED}[${timestamp}] [ERROR]${NC} ${message}" | tee -a "${LOG_FILE}"
            ;;
        CHAOS)
            echo -e "${BLUE}[${timestamp}] [CHAOS]${NC} ${message}" | tee -a "${LOG_FILE}"
            ;;
        *)
            echo "[${timestamp}] ${message}" | tee -a "${LOG_FILE}"
            ;;
    esac
}

# Random number generator
random_int() {
    local min="$1"
    local max="$2"
    echo $(( RANDOM % (max - min + 1) + min ))
}

# Get random VM from list
get_random_vm() {
    local vm_count=${#VMS[@]}
    local index=$(random_int 0 $((vm_count - 1)))
    echo "${VMS[$index]}"
}

# Get random scenario
get_random_scenario() {
    local scenario_count=${#SCENARIOS[@]}
    local index=$(random_int 0 $((scenario_count - 1)))
    echo "${SCENARIOS[$index]}"
}

# Chaos Scenario: VM Stop (Hardware Failure)
chaos_vm_stop() {
    local vm="$1"

    log CHAOS "💥 Injecting VM stop failure on ${vm}"

    # Check if VM is running
    local vm_phase=$(oc get vmi "${vm}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

    if [ "${vm_phase}" != "Running" ]; then
        log WARN "VM ${vm} is not running (phase: ${vm_phase}), skipping"
        return 1
    fi

    # Stop the VM
    virtctl stop "${vm}" -n "${NAMESPACE}" 2>&1 | tee -a "${LOG_FILE}"

    log INFO "VM ${vm} stopped. Monitoring recovery..."

    # Wait for automatic recovery (if orchestrated)
    sleep 30

    # Check if VM restarted automatically (unlikely in this workshop)
    vm_phase=$(oc get vmi "${vm}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

    if [ "${vm_phase}" == "Running" ]; then
        log INFO "✓ VM ${vm} recovered automatically"
    else
        log WARN "VM ${vm} requires manual restart (virtctl start ${vm} -n ${NAMESPACE})"
    fi
}

# Chaos Scenario: Network Partition (via firewall rule)
chaos_network_partition() {
    local vm="$1"

    log CHAOS "🔥 Injecting network partition on ${vm}"

    # Determine target IP based on VM
    local target_ip=""
    case "${vm}" in
        rhel-ha-node1)
            target_ip="10.101.0.21"  # Block node2
            ;;
        rhel-ha-node2)
            target_ip="10.101.0.20"  # Block node1
            ;;
        microshift-gw-a)
            target_ip="10.102.0.21"  # Block gw-b
            ;;
        microshift-gw-b)
            target_ip="10.102.0.20"  # Block gw-a
            ;;
        twonode-master1)
            target_ip="10.103.0.21"  # Block master2
            ;;
        twonode-master2)
            target_ip="10.103.0.20"  # Block master1
            ;;
        *)
            log WARN "Unknown VM ${vm} for network partition, skipping"
            return 1
            ;;
    esac

    # Inject firewall rule to drop packets
    virtctl ssh redhat@"${vm}" -n "${NAMESPACE}" -- \
        sudo firewall-cmd --direct --add-rule ipv4 filter INPUT 0 -s "${target_ip}" -j DROP \
        2>&1 | tee -a "${LOG_FILE}"

    log INFO "Network partition created on ${vm} (blocking ${target_ip})"

    # Wait for failure detection (30-60 seconds typically)
    sleep 60

    # Remove the partition (self-healing)
    virtctl ssh redhat@"${vm}" -n "${NAMESPACE}" -- \
        sudo firewall-cmd --direct --remove-rule ipv4 filter INPUT 0 -s "${target_ip}" -j DROP \
        2>&1 | tee -a "${LOG_FILE}"

    log INFO "✓ Network partition healed on ${vm}"
}

# Chaos Scenario: CPU Saturation
chaos_cpu_saturation() {
    local vm="$1"

    log CHAOS "⚡ Injecting CPU saturation on ${vm}"

    # Check if stress-ng is available, fallback to yes command
    local stress_cmd="stress-ng --cpu 2 --timeout 30s"

    virtctl ssh redhat@"${vm}" -n "${NAMESPACE}" -- \
        "command -v stress-ng >/dev/null 2>&1 || stress_cmd='for i in {1..2}; do yes > /dev/null & done; sleep 30; killall yes'" \
        2>&1 | tee -a "${LOG_FILE}"

    # Run stress test in background
    virtctl ssh redhat@"${vm}" -n "${NAMESPACE}" -- \
        "nohup sh -c '${stress_cmd}' > /dev/null 2>&1 &" \
        2>&1 | tee -a "${LOG_FILE}"

    log INFO "CPU stress applied to ${vm} for 30 seconds"

    # Wait for stress to complete
    sleep 35

    log INFO "✓ CPU stress completed on ${vm}"
}

# Chaos Scenario: Process Crash
chaos_process_crash() {
    local vm="$1"

    log CHAOS "💀 Injecting process crash on ${vm}"

    # Determine critical process based on VM type
    local process=""
    case "${vm}" in
        rhel-ha-node*)
            process="corosync"
            ;;
        microshift-gw-*)
            process="kube-apiserver"
            ;;
        twonode-*)
            # Skip process crash for two-node (simulated cluster)
            log WARN "Process crash skipped for ${vm} (simulated cluster)"
            return 0
            ;;
        *)
            log WARN "Unknown VM ${vm} for process crash, skipping"
            return 1
            ;;
    esac

    # Kill the process
    virtctl ssh redhat@"${vm}" -n "${NAMESPACE}" -- \
        "sudo pkill -9 ${process}" \
        2>&1 | tee -a "${LOG_FILE}"

    log INFO "Process ${process} killed on ${vm}"

    # Wait for automatic restart (systemd should restart)
    sleep 10

    # Verify process restarted
    local is_running=$(virtctl ssh redhat@"${vm}" -n "${NAMESPACE}" -- \
        "pgrep ${process} >/dev/null && echo yes || echo no" 2>/dev/null || echo "unknown")

    if [ "${is_running}" == "yes" ]; then
        log INFO "✓ Process ${process} restarted automatically on ${vm}"
    else
        log WARN "Process ${process} did not restart on ${vm} (may require manual intervention)"
    fi
}

# Execute random chaos scenario
inject_chaos() {
    local vm=$(get_random_vm)
    local scenario=$(get_random_scenario)

    log INFO "Selected chaos scenario: ${scenario} on VM: ${vm}"

    case "${scenario}" in
        vm_stop)
            chaos_vm_stop "${vm}"
            ;;
        network_partition)
            chaos_network_partition "${vm}"
            ;;
        cpu_saturation)
            chaos_cpu_saturation "${vm}"
            ;;
        process_crash)
            chaos_process_crash "${vm}"
            ;;
        *)
            log ERROR "Unknown scenario: ${scenario}"
            return 1
            ;;
    esac
}

# Cleanup function
cleanup() {
    log INFO "GameDay ended. Cleaning up..."

    # Remove any lingering firewall rules
    for vm in "${VMS[@]}"; do
        local vm_phase=$(oc get vmi "${vm}" -n "${NAMESPACE}" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

        if [ "${vm_phase}" == "Running" ]; then
            # Attempt to clean up firewall rules
            virtctl ssh redhat@"${vm}" -n "${NAMESPACE}" -- \
                "sudo firewall-cmd --direct --get-all-rules 2>/dev/null | grep 'INPUT.*DROP' | while read rule; do sudo firewall-cmd --direct --remove-rule \$rule 2>/dev/null || true; done" \
                2>&1 | tee -a "${LOG_FILE}"
        fi
    done

    log INFO "Cleanup complete. Log saved to: ${LOG_FILE}"
}

trap cleanup EXIT INT TERM

# Main GameDay loop
main() {
    echo "=========================================="
    echo "🔥 Chaos Engineering GameDay 🔥"
    echo "=========================================="
    echo "Namespace:     ${NAMESPACE}"
    echo "Duration:      ${DURATION_MINUTES} minutes"
    echo "Failure Rate:  ${FAILURE_RATE} (every ${MIN_INTERVAL}-${MAX_INTERVAL}s)"
    echo "Log File:      ${LOG_FILE}"
    echo "=========================================="
    echo ""

    log INFO "GameDay started!"
    log INFO "Press Ctrl+C to stop early"

    local end_time=$(($(date +%s) + (DURATION_MINUTES * 60)))
    local chaos_count=0

    while [ $(date +%s) -lt ${end_time} ]; do
        # Inject chaos
        inject_chaos
        ((chaos_count++))

        # Calculate next chaos injection time
        local next_interval=$(random_int ${MIN_INTERVAL} ${MAX_INTERVAL})
        local remaining=$((end_time - $(date +%s)))

        if [ ${remaining} -lt ${next_interval} ]; then
            log INFO "Less than ${next_interval}s remaining. Ending GameDay."
            break
        fi

        log INFO "Next chaos injection in ${next_interval} seconds (${remaining}s remaining in GameDay)"
        sleep ${next_interval}
    done

    echo ""
    echo "=========================================="
    echo "GameDay Complete!"
    echo "=========================================="
    echo "Total chaos injections: ${chaos_count}"
    echo "Duration: ${DURATION_MINUTES} minutes"
    echo "Log: ${LOG_FILE}"
    echo ""
    echo "Run post-chaos validation:"
    echo "  oc get vmi -n ${NAMESPACE}"
    echo "  # Check each VM's status"
    echo "=========================================="
}

# Validate prerequisites
if ! command -v oc &> /dev/null; then
    echo "ERROR: oc CLI not found. Please install OpenShift CLI."
    exit 1
fi

if ! command -v virtctl &> /dev/null; then
    echo "ERROR: virtctl not found. Please install virtctl."
    exit 1
fi

if ! oc get namespace "${NAMESPACE}" &> /dev/null; then
    echo "ERROR: Namespace ${NAMESPACE} does not exist."
    exit 1
fi

# Run the GameDay!
main
