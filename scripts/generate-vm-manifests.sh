#!/bin/bash
# =============================================================================
# Generate VirtualMachine Manifests for All Students
# =============================================================================
# This script generates VM manifests for a specified number of students.
# Each student gets VMs for all 3 modules:
#   - Module 1 (RHEL HA): 2 VMs
#   - Module 2 (MicroShift): 2 VMs
#   - Module 3 (Two-Node): 3 VMs
#   Total: 7 VMs per student
#
# Usage:
#   ./scripts/generate-vm-manifests.sh [student-count]
#
# Example:
#   ./scripts/generate-vm-manifests.sh 50
# =============================================================================

set -e

STUDENT_COUNT=${1:-50}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

echo "=========================================="
echo "Generating VM Manifests"
echo "=========================================="
echo "Student count: ${STUDENT_COUNT}"
echo ""

# Module 1: RHEL HA Node 1
MODULE1_NODE1_VM="${REPO_ROOT}/manifests/vms/module1-rhel-ha/vm-rhel-node1.yaml"
MODULE1_NODE1_INIT="${REPO_ROOT}/manifests/vms/module1-rhel-ha/cloudinit-node1.yaml"

echo "Generating Module 1 (RHEL HA) VMs..."

# Generate vm-rhel-node1.yaml
cat > "${MODULE1_NODE1_VM}" << 'VMEOF'
# =============================================================================
# VirtualMachine - Module 1: RHEL HA Node 1
# =============================================================================
# Generated for ${STUDENT_COUNT} students
# Static IP: 10.101.0.20 (on pacemaker-net)
# =============================================================================

VMEOF

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v student_id "%02d" "$i"
cat >> "${MODULE1_NODE1_VM}" << EOF

---
# Student ${student_id} - RHEL HA Node 1
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: rhel-ha-node1
  namespace: retail-edge-student-${student_id}
  labels:
    app: rhel-ha
    module: module1
    node: node1
    student-id: "${student_id}"
    app.kubernetes.io/name: rhel-ha-node1
    app.kubernetes.io/part-of: retail-edge-ha
spec:
  running: false
  dataVolumeTemplates:
  - apiVersion: cdi.kubevirt.io/v1beta1
    kind: DataVolume
    metadata:
      name: rhel-ha-node1-disk
    spec:
      source:
        http:
          url: "https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
      storage:
        resources:
          requests:
            storage: 30Gi
        storageClassName: ocs-external-storagecluster-ceph-rbd
        accessModes:
          - ReadWriteOnce
  template:
    metadata:
      labels:
        kubevirt.io/domain: rhel-ha-node1
        module: module1
    spec:
      domain:
        cpu:
          cores: 2
          sockets: 1
          threads: 1
        devices:
          disks:
          - disk:
              bus: virtio
            name: rootdisk
          - disk:
              bus: virtio
            name: cloudinitdisk
          interfaces:
          - name: default
            masquerade: {}
          - name: pacemaker-net
            bridge: {}
          networkInterfaceMultiqueue: true
          rng: {}
        resources:
          requests:
            memory: 4Gi
      networks:
      - name: default
        pod: {}
      - name: pacemaker-net
        multus:
          networkName: retail-edge-student-${i}-udn/pacemaker-net
      volumes:
      - dataVolume:
          name: rhel-ha-node1-disk
        name: rootdisk
      - cloudInitNoCloud:
          secretRef:
            name: rhel-ha-node1-cloudinit
        name: cloudinitdisk
EOF
done

echo "✓ Generated vm-rhel-node1.yaml for ${STUDENT_COUNT} students"

# Generate cloudinit-node1.yaml
cat > "${MODULE1_NODE1_INIT}" << 'INITEOF'
# =============================================================================
# Cloud-init Configuration - RHEL HA Node 1
# =============================================================================
# Generated for ${STUDENT_COUNT} students
# Static IP: 10.101.0.20 on eth1 (pacemaker-net)
# =============================================================================

INITEOF

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v student_id "%02d" "$i"
cat >> "${MODULE1_NODE1_INIT}" << EOF

---
# Student ${student_id} - Node 1 Cloud-init
apiVersion: v1
kind: Secret
metadata:
  name: rhel-ha-node1-cloudinit
  namespace: retail-edge-student-${student_id}
type: Opaque
stringData:
  userdata: |
    #cloud-config
    user: cloud-user
    password: redhat
    chpasswd:
      expire: false
    ssh_pwauth: true
    packages:
      - pacemaker
      - pcs
      - fence-agents-kubevirt
      - corosync
      - fence-agents-all
    runcmd:
      - systemctl enable --now pcsd
      - echo "redhat" | passwd --stdin hacluster
      - hostnamectl set-hostname rhel-ha-node1
      - nmcli con mod "Wired connection 2" ipv4.addresses 10.101.0.20/24
      - nmcli con mod "Wired connection 2" ipv4.method manual
      - nmcli con mod "Wired connection 2" connection.autoconnect yes
      - nmcli con up "Wired connection 2"
      - echo "10.101.0.20 rhel-ha-node1" >> /etc/hosts
      - echo "10.101.0.21 rhel-ha-node2" >> /etc/hosts
EOF
done

echo "✓ Generated cloudinit-node1.yaml for ${STUDENT_COUNT} students"

# TODO: Generate Node 2, Module 2, and Module 3 VMs
# (Add similar loops for vm-rhel-node2, module2, module3)

echo ""
echo "=========================================="
echo "✅ VM Generation Complete!"
echo "=========================================="
echo ""
echo "Total VMs generated: $(( STUDENT_COUNT * 2 ))"
echo "  - Module 1 Node 1: ${STUDENT_COUNT}"
echo "  - Module 1 Node 2: Not yet implemented"
echo "  - Module 2: Not yet implemented"
echo "  - Module 3: Not yet implemented"
echo ""
echo "Files updated:"
echo "  - ${MODULE1_NODE1_VM}"
echo "  - ${MODULE1_NODE1_INIT}"
echo ""
