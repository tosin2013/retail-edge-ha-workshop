#!/bin/bash
# =============================================================================
# Generate User Defined Network (UDN) Manifests for All Students
# =============================================================================
# This script generates UDN manifests for a specified number of students.
# Each student gets 3 UDNs (one per module) in their VM namespace.
#
# Usage:
#   ./scripts/generate-udn-manifests.sh [student-count]
#
# Example:
#   ./scripts/generate-udn-manifests.sh 50
# =============================================================================

set -e

STUDENT_COUNT=${1:-50}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=========================================="
echo "Generating UDN Manifests"
echo "=========================================="
echo "Student count: ${STUDENT_COUNT}"
echo ""

# Module 1: Pacemaker Network
MODULE1_FILE="${REPO_ROOT}/manifests/networking/udn-module1/udn-pacemaker.yaml"
echo "# =============================================================================
# User Defined Network - Module 1: RHEL HA with Pacemaker
# =============================================================================
# This UDN provides Layer 2 networking for Corosync cluster heartbeat.
# OVN-K IPAM assigns IPs from the subnet; lifecycle: Persistent ensures IPs
# are stored in IPAMClaim objects and survive VM restarts (including STONITH
# fencing). Pre-created IPAMClaims pin each VM to a known static IP.
#
# References:
#   - RHEL HA cluster config (static IPs required for Corosync):
#     https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/configuring_and_managing_high_availability_clusters/assembly_creating-high-availability-cluster-configuring-and-managing-high-availability-clusters
#   - OCP 4.21 UDN API (ipam.lifecycle: Persistent):
#     https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/network_apis/userdefinednetwork-k8s-ovn-org-v1
#
# Network Details:
#   - Purpose: Pacemaker cluster heartbeat and fence_kubevirt communication
#   - Subnet: 10.101.0.0/24
#   - VMs per student: 2 (rhel-ha-node1, rhel-ha-node2)
#   - Static IPs (via IPAMClaim): node1=10.101.0.20, node2=10.101.0.21
#
# Generated for ${STUDENT_COUNT} students
# =============================================================================
" > "${MODULE1_FILE}"

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v student_id "%02d" "$i"
cat >> "${MODULE1_FILE}" << EOF

---
# Student ${student_id} - Pacemaker Network
apiVersion: k8s.ovn.org/v1
kind: UserDefinedNetwork
metadata:
  name: pacemaker-net
  namespace: retail-edge-student-${student_id}
  labels:
    workshop: retail-edge-ha
    module: module1
    student-id: "${student_id}"
  annotations:
    description: "Layer 2 network for RHEL HA Pacemaker cluster heartbeat"
spec:
  topology: Layer2
  layer2:
    role: Secondary
    subnets:
    - "10.101.0.0/24"
    ipam:
      mode: Enabled
      lifecycle: Persistent
EOF
done

echo "✓ Generated Module 1 (Pacemaker) UDNs: ${STUDENT_COUNT} students"

# Module 2: MicroShift Network
MODULE2_FILE="${REPO_ROOT}/manifests/networking/udn-module2/udn-microshift.yaml"
echo "# =============================================================================
# User Defined Network - Module 2: MicroShift with VRRP
# =============================================================================
# This UDN provides Layer 2 networking for VRRP (Virtual Router Redundancy
# Protocol) virtual IP failover. VRRP requires Layer 2 for multicast
# advertisements (224.0.0.18) and ARP replies for the Virtual IP.
#
# OVN-K IPAM assigns IPs from the subnet; lifecycle: Persistent ensures IPs
# survive VM restarts. Pre-created IPAMClaims pin each VM to a known static IP.
#
# References:
#   - OCP 4.21 UDN API (ipam.lifecycle: Persistent):
#     https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/network_apis/userdefinednetwork-k8s-ovn-org-v1
#
# Network Details:
#   - Purpose: MicroShift VRRP failover for Point-of-Sale applications
#   - Subnet: 10.102.0.0/24
#   - VMs per student: 2 (microshift-gw-a, microshift-gw-b)
#   - Static IPs (via IPAMClaim): gw-a=10.102.0.20, gw-b=10.102.0.21
#
# Generated for ${STUDENT_COUNT} students
# =============================================================================
" > "${MODULE2_FILE}"

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v student_id "%02d" "$i"
cat >> "${MODULE2_FILE}" << EOF

---
# Student ${student_id} - MicroShift VRRP Network
apiVersion: k8s.ovn.org/v1
kind: UserDefinedNetwork
metadata:
  name: microshift-net
  namespace: retail-edge-student-${student_id}
  labels:
    workshop: retail-edge-ha
    module: module2
    student-id: "${student_id}"
  annotations:
    description: "Layer 2 network for MicroShift VRRP virtual IP failover"
spec:
  topology: Layer2
  layer2:
    role: Secondary
    subnets:
    - "10.102.0.0/24"
    ipam:
      mode: Enabled
      lifecycle: Persistent
EOF
done

echo "✓ Generated Module 2 (MicroShift) UDNs: ${STUDENT_COUNT} students"

# Module 3: Two-Node OpenShift Network
MODULE3_FILE="${REPO_ROOT}/manifests/networking/udn-module3/udn-twonode.yaml"
echo "# =============================================================================
# User Defined Network - Module 3: OpenShift Two-Node with Arbiter
# =============================================================================
# This UDN provides Layer 2 networking for two-node OpenShift cluster
# communication. While etcd works over Layer 3, the low-latency Layer 2
# network reduces heartbeat failures and simulates a realistic retail edge
# network topology.
#
# Network Details:
#   - CIDR: 10.103.0.0/24
#   - Gateway: 10.103.0.1
#   - Purpose: Two-node OpenShift cluster communication + remote arbiter
#   - VMs per student: 3 (2 control-plane + 1 arbiter)
#
# IP Allocation per Student:
#   - Student 01: 10.103.0.20-22 (master1, master2, arbiter)
#   - Student 02: 10.103.0.20-22 (isolated UDN, same IPs OK)
#   - Student 03-50: Same pattern (each in their own namespace)
#
# Generated for ${STUDENT_COUNT} students
# =============================================================================
" > "${MODULE3_FILE}"

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v student_id "%02d" "$i"
cat >> "${MODULE3_FILE}" << EOF

---
# Student ${student_id} - Two-Node OpenShift Network
apiVersion: k8s.ovn.org/v1
kind: UserDefinedNetwork
metadata:
  name: twonode-net
  namespace: retail-edge-student-${student_id}
  labels:
    workshop: retail-edge-ha
    module: module3
    student-id: "${student_id}"
  annotations:
    description: "Layer 2 network for OpenShift two-node cluster with arbiter"
spec:
  topology: Layer2
  layer2:
    role: Secondary
    subnets:
    - "10.103.0.0/24"
EOF
done

echo "✓ Generated Module 3 (Two-Node) UDNs: ${STUDENT_COUNT} students"
echo ""
echo "=========================================="
echo "✅ UDN Generation Complete!"
echo "=========================================="
echo ""
echo "Total UDNs generated: $((STUDENT_COUNT * 3))"
echo "  - Module 1 (Pacemaker): ${STUDENT_COUNT}"
echo "  - Module 2 (MicroShift): ${STUDENT_COUNT}"
echo "  - Module 3 (Two-Node): ${STUDENT_COUNT}"
echo ""
echo "Files updated:"
echo "  - ${MODULE1_FILE}"
echo "  - ${MODULE2_FILE}"
echo "  - ${MODULE3_FILE}"
echo ""
