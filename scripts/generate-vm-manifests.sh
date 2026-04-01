#!/bin/bash
# =============================================================================
# Generate VirtualMachine Manifests for All Students
# =============================================================================
# Generates VM manifests for all 3 modules by replicating Student 01 blocks.
# Reads student count from values.yaml or accepts it as a CLI argument.
#
# Each student gets VMs for all 3 modules:
#   - Module 1 (RHEL HA): 2 VMs + 2 cloud-init secrets
#   - Module 2 (MicroShift): 2 VMs + 2 cloud-init secrets
#   - Module 3 (Two-Node): 3 VMs + 1 ignition placeholder secret
#   Total: 7 VMs per student
#
# Usage:
#   ./scripts/generate-vm-manifests.sh [student-count]
#
# Examples:
#   ./scripts/generate-vm-manifests.sh        # reads count from values.yaml
#   ./scripts/generate-vm-manifests.sh 25     # override to 25 students
# =============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VALUES_FILE="${REPO_ROOT}/helm/retail-edge-ha/values.yaml"

# Read student count: CLI arg > values.yaml > default 2
if [[ -n "$1" ]]; then
  STUDENT_COUNT="$1"
elif command -v yq &>/dev/null; then
  STUDENT_COUNT=$(yq '.students.count' "$VALUES_FILE" 2>/dev/null || echo 2)
else
  # Fallback: grep from values.yaml
  STUDENT_COUNT=$(grep -A1 'students:' "$VALUES_FILE" | grep 'count:' | awk '{print $2}' || echo 2)
fi
STUDENT_COUNT=${STUDENT_COUNT:-2}

# Read storage class from values.yaml
if command -v yq &>/dev/null; then
  STORAGE_CLASS=$(yq '.virtualMachines.storageClass' "$VALUES_FILE" 2>/dev/null || echo "ocs-external-storagecluster-ceph-rbd-immediate")
else
  STORAGE_CLASS=$(grep 'storageClass:' "$VALUES_FILE" | head -1 | awk -F'"' '{print $2}' || echo "ocs-external-storagecluster-ceph-rbd-immediate")
fi
STORAGE_CLASS=${STORAGE_CLASS:-ocs-external-storagecluster-ceph-rbd-immediate}

NAMESPACE_PREFIX="retail-edge-student"

echo "=========================================="
echo "Generating VM Manifests"
echo "=========================================="
echo "Student count:  ${STUDENT_COUNT}"
echo "Storage class:  ${STORAGE_CLASS}"
echo "Namespace:      ${NAMESPACE_PREFIX}-XX"
echo ""

# =============================================================================
# Helper: generate_per_student <output_file> <header> <body_func>
#   Writes a header then calls body_func for each student
# =============================================================================
write_header() {
  local file="$1" header="$2"
  cat > "$file" <<EOF
${header}
EOF
}

# =============================================================================
# MODULE 1: RHEL HA with Pacemaker
# =============================================================================
echo "--- Module 1: RHEL HA ---"

M1_DIR="${REPO_ROOT}/manifests/vms/module1-rhel-ha"

# -- vm-rhel-node1.yaml --
M1_NODE1_VM="${M1_DIR}/vm-rhel-node1.yaml"
write_header "$M1_NODE1_VM" "# VirtualMachine - Module 1: RHEL HA Node 1
# Generated for ${STUDENT_COUNT} students | Storage: ${STORAGE_CLASS}"

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v sid "%02d" "$i"
  cat >> "$M1_NODE1_VM" <<EOF

---
# Student ${sid} - RHEL HA Node 1
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: rhel-ha-node1
  namespace: ${NAMESPACE_PREFIX}-${sid}
  labels:
    app: rhel-ha
    module: module1
    node: node1
    student-id: "${sid}"
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
        storageClassName: ${STORAGE_CLASS}
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
          networkName: ${NAMESPACE_PREFIX}-${sid}-udn/pacemaker-net
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
echo "  vm-rhel-node1.yaml"

# -- vm-rhel-node2.yaml --
M1_NODE2_VM="${M1_DIR}/vm-rhel-node2.yaml"
write_header "$M1_NODE2_VM" "# VirtualMachine - Module 1: RHEL HA Node 2
# Generated for ${STUDENT_COUNT} students | Storage: ${STORAGE_CLASS}"

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v sid "%02d" "$i"
  cat >> "$M1_NODE2_VM" <<EOF

---
# Student ${sid} - RHEL HA Node 2
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: rhel-ha-node2
  namespace: ${NAMESPACE_PREFIX}-${sid}
  labels:
    app: rhel-ha
    module: module1
    node: node2
    student-id: "${sid}"
    app.kubernetes.io/name: rhel-ha-node2
    app.kubernetes.io/part-of: retail-edge-ha
spec:
  running: false
  dataVolumeTemplates:
  - apiVersion: cdi.kubevirt.io/v1beta1
    kind: DataVolume
    metadata:
      name: rhel-ha-node2-disk
    spec:
      source:
        http:
          url: "https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
      storage:
        resources:
          requests:
            storage: 30Gi
        storageClassName: ${STORAGE_CLASS}
        accessModes:
          - ReadWriteOnce
  template:
    metadata:
      labels:
        kubevirt.io/domain: rhel-ha-node2
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
          networkName: ${NAMESPACE_PREFIX}-${sid}-udn/pacemaker-net
      volumes:
      - dataVolume:
          name: rhel-ha-node2-disk
        name: rootdisk
      - cloudInitNoCloud:
          secretRef:
            name: rhel-ha-node2-cloudinit
        name: cloudinitdisk
EOF
done
echo "  vm-rhel-node2.yaml"

# -- cloudinit-node1.yaml --
M1_INIT1="${M1_DIR}/cloudinit-node1.yaml"
write_header "$M1_INIT1" "# Cloud-init - RHEL HA Node 1
# Generated for ${STUDENT_COUNT} students | IP: 10.101.0.20"

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v sid "%02d" "$i"
  cat >> "$M1_INIT1" <<EOF

---
# Student ${sid} - Node 1 Cloud-init
apiVersion: v1
kind: Secret
metadata:
  name: rhel-ha-node1-cloudinit
  namespace: ${NAMESPACE_PREFIX}-${sid}
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
echo "  cloudinit-node1.yaml"

# -- cloudinit-node2.yaml --
M1_INIT2="${M1_DIR}/cloudinit-node2.yaml"
write_header "$M1_INIT2" "# Cloud-init - RHEL HA Node 2
# Generated for ${STUDENT_COUNT} students | IP: 10.101.0.21"

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v sid "%02d" "$i"
  cat >> "$M1_INIT2" <<EOF

---
# Student ${sid} - Node 2 Cloud-init
apiVersion: v1
kind: Secret
metadata:
  name: rhel-ha-node2-cloudinit
  namespace: ${NAMESPACE_PREFIX}-${sid}
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
      - hostnamectl set-hostname rhel-ha-node2
      - nmcli con mod "Wired connection 2" ipv4.addresses 10.101.0.21/24
      - nmcli con mod "Wired connection 2" ipv4.method manual
      - nmcli con mod "Wired connection 2" connection.autoconnect yes
      - nmcli con up "Wired connection 2"
      - echo "10.101.0.20 rhel-ha-node1" >> /etc/hosts
      - echo "10.101.0.21 rhel-ha-node2" >> /etc/hosts
EOF
done
echo "  cloudinit-node2.yaml"

# =============================================================================
# MODULE 2: MicroShift with VRRP
# =============================================================================
echo ""
echo "--- Module 2: MicroShift ---"

M2_DIR="${REPO_ROOT}/manifests/vms/module2-microshift"

# -- vm-microshift-gw-a.yaml --
M2_GWA_VM="${M2_DIR}/vm-microshift-gw-a.yaml"
write_header "$M2_GWA_VM" "# VirtualMachine - Module 2: MicroShift Gateway A
# Generated for ${STUDENT_COUNT} students | Storage: ${STORAGE_CLASS}"

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v sid "%02d" "$i"
  cat >> "$M2_GWA_VM" <<EOF

---
# Student ${sid} - MicroShift Gateway A
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: microshift-gw-a
  namespace: ${NAMESPACE_PREFIX}-${sid}
  labels:
    app: microshift
    module: module2
    node: gw-a
    student-id: "${sid}"
    app.kubernetes.io/name: microshift-gw-a
    app.kubernetes.io/part-of: retail-edge-ha
spec:
  running: false
  dataVolumeTemplates:
  - apiVersion: cdi.kubevirt.io/v1beta1
    kind: DataVolume
    metadata:
      name: microshift-gw-a-disk
    spec:
      source:
        http:
          url: "https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
      storage:
        resources:
          requests:
            storage: 40Gi
        storageClassName: ${STORAGE_CLASS}
        accessModes:
          - ReadWriteOnce
  template:
    metadata:
      labels:
        kubevirt.io/domain: microshift-gw-a
        module: module2
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
          - name: microshift-net
            bridge: {}
          networkInterfaceMultiqueue: true
          rng: {}
        resources:
          requests:
            memory: 4Gi
      networks:
      - name: default
        pod: {}
      - name: microshift-net
        multus:
          networkName: ${NAMESPACE_PREFIX}-${sid}-udn/microshift-net
      volumes:
      - dataVolume:
          name: microshift-gw-a-disk
        name: rootdisk
      - cloudInitNoCloud:
          secretRef:
            name: cloudinit-microshift-gw-a
        name: cloudinitdisk
EOF
done
echo "  vm-microshift-gw-a.yaml"

# -- vm-microshift-gw-b.yaml --
M2_GWB_VM="${M2_DIR}/vm-microshift-gw-b.yaml"
write_header "$M2_GWB_VM" "# VirtualMachine - Module 2: MicroShift Gateway B
# Generated for ${STUDENT_COUNT} students | Storage: ${STORAGE_CLASS}"

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v sid "%02d" "$i"
  cat >> "$M2_GWB_VM" <<EOF

---
# Student ${sid} - MicroShift Gateway B
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: microshift-gw-b
  namespace: ${NAMESPACE_PREFIX}-${sid}
  labels:
    app: microshift
    module: module2
    node: gw-b
    student-id: "${sid}"
    app.kubernetes.io/name: microshift-gw-b
    app.kubernetes.io/part-of: retail-edge-ha
spec:
  running: false
  dataVolumeTemplates:
  - apiVersion: cdi.kubevirt.io/v1beta1
    kind: DataVolume
    metadata:
      name: microshift-gw-b-disk
    spec:
      source:
        http:
          url: "https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2"
      storage:
        resources:
          requests:
            storage: 40Gi
        storageClassName: ${STORAGE_CLASS}
        accessModes:
          - ReadWriteOnce
  template:
    metadata:
      labels:
        kubevirt.io/domain: microshift-gw-b
        module: module2
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
          - name: microshift-net
            bridge: {}
          networkInterfaceMultiqueue: true
          rng: {}
        resources:
          requests:
            memory: 4Gi
      networks:
      - name: default
        pod: {}
      - name: microshift-net
        multus:
          networkName: ${NAMESPACE_PREFIX}-${sid}-udn/microshift-net
      volumes:
      - dataVolume:
          name: microshift-gw-b-disk
        name: rootdisk
      - cloudInitNoCloud:
          secretRef:
            name: cloudinit-microshift-gw-b
        name: cloudinitdisk
EOF
done
echo "  vm-microshift-gw-b.yaml"

# Cloud-init for Module 2 is complex (keepalived configs). We preserve it as-is
# by replicating the Student 01 block from the existing files. The cloud-init
# content is identical across students; only the namespace differs.
for gw in gw-a gw-b; do
  INIT_FILE="${M2_DIR}/cloudinit-${gw}.yaml"
  if [[ -f "$INIT_FILE" ]]; then
    # Extract student-01 block (from first --- to second ---)
    BLOCK=$(awk '/^---$/{ if(n++) exit } n' "$INIT_FILE")

    HEADER="# Cloud-init - Module 2: MicroShift ${gw}
# Generated for ${STUDENT_COUNT} students"
    echo "$HEADER" > "${INIT_FILE}.tmp"

    for ((i=1; i<=STUDENT_COUNT; i++)); do
      printf -v sid "%02d" "$i"
      echo "" >> "${INIT_FILE}.tmp"
      echo "---" >> "${INIT_FILE}.tmp"
      echo "$BLOCK" | sed \
        -e "s/Student 01/Student ${sid}/g" \
        -e "s/${NAMESPACE_PREFIX}-01/${NAMESPACE_PREFIX}-${sid}/g" \
        >> "${INIT_FILE}.tmp"
    done
    mv "${INIT_FILE}.tmp" "$INIT_FILE"
    echo "  cloudinit-${gw}.yaml"
  fi
done

# =============================================================================
# MODULE 3: Two-Node OpenShift with Arbiter
# =============================================================================
echo ""
echo "--- Module 3: Two-Node OpenShift ---"

M3_DIR="${REPO_ROOT}/manifests/vms/module3-twonode"

# Module 3 uses PVC clone source (not HTTP), ignition (not cloud-init),
# and has EFI firmware. Generate VMs for master1, master2, arbiter.

generate_m3_vm() {
  local vm_name="$1" disk_name="$2" disk_size="$3" role="$4" \
        role_label="$5" cores="$6" memory="$7" ignition_secret="$8" \
        output_file="$9"

  write_header "$output_file" "# VirtualMachine - Module 3: Two-Node OpenShift ${vm_name}
# Generated for ${STUDENT_COUNT} students | Storage: ${STORAGE_CLASS}"

  for ((i=1; i<=STUDENT_COUNT; i++)); do
    printf -v sid "%02d" "$i"
    cat >> "$output_file" <<EOF

---
# Student ${sid} - Two-Node ${role}
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: ${vm_name}
  namespace: ${NAMESPACE_PREFIX}-${sid}
  labels:
    app: twonode-ocp
    module: module3
    node: ${vm_name##twonode-}
    role: ${role_label}
    student-id: "${sid}"
    app.kubernetes.io/name: ${vm_name}
    app.kubernetes.io/part-of: retail-edge-ha
spec:
  running: false
  dataVolumeTemplates:
  - apiVersion: cdi.kubevirt.io/v1beta1
    kind: DataVolume
    metadata:
      name: ${disk_name}
    spec:
      source:
        pvc:
          namespace: retail-edge-infrastructure
          name: rhcos-image
      storage:
        resources:
          requests:
            storage: ${disk_size}
        storageClassName: ${STORAGE_CLASS}
        accessModes:
          - ReadWriteOnce
  template:
    metadata:
      labels:
        kubevirt.io/domain: ${vm_name}
        module: module3
        role: ${role_label}
    spec:
      domain:
        cpu:
          cores: ${cores}
          sockets: 1
          threads: 1
        devices:
          disks:
          - disk:
              bus: virtio
            name: rootdisk
          - disk:
              bus: virtio
            name: ignitiondisk
          interfaces:
          - name: default
            masquerade: {}
          - name: twonode-net
            bridge: {}
          networkInterfaceMultiqueue: true
          rng: {}
        firmware:
          bootloader:
            efi:
              secureBoot: false
        resources:
          requests:
            memory: ${memory}
      networks:
      - name: default
        pod: {}
      - name: twonode-net
        multus:
          networkName: ${NAMESPACE_PREFIX}-${sid}-udn/twonode-net
      volumes:
      - dataVolume:
          name: ${disk_name}
        name: rootdisk
      - secret:
          secretName: ${ignition_secret}
        name: ignitiondisk
EOF
  done
}

generate_m3_vm "twonode-master1" "twonode-master1-disk" "120Gi" "Master 1" \
  "control-plane" 4 "16Gi" "ignition-twonode-master1" "${M3_DIR}/vm-twonode-master1.yaml"
echo "  vm-twonode-master1.yaml"

generate_m3_vm "twonode-master2" "twonode-master2-disk" "120Gi" "Master 2" \
  "control-plane" 4 "16Gi" "ignition-twonode-master2" "${M3_DIR}/vm-twonode-master2.yaml"
echo "  vm-twonode-master2.yaml"

generate_m3_vm "twonode-arbiter" "twonode-arbiter-disk" "20Gi" "Arbiter" \
  "etcd-arbiter" 1 "2Gi" "ignition-twonode-arbiter" "${M3_DIR}/vm-twonode-arbiter.yaml"
echo "  vm-twonode-arbiter.yaml"

# Ignition placeholders - replicate existing student-01 blocks
IGN_FILE="${M3_DIR}/ignition-placeholder.yaml"
if [[ -f "$IGN_FILE" ]]; then
  # The ignition file has multiple blocks (master1, master2, arbiter per student).
  # Extract the three student-01 blocks and replicate per student.
  HEADER="# Ignition Configuration Placeholders - Module 3: Two-Node OpenShift
# Generated for ${STUDENT_COUNT} students
# IMPORTANT: These are PLACEHOLDER secrets. Generate proper ignition via openshift-install."
  echo "$HEADER" > "${IGN_FILE}.tmp"

  for vm_role in master1 master2 arbiter; do
    for ((i=1; i<=STUDENT_COUNT; i++)); do
      printf -v sid "%02d" "$i"
      if [[ "$vm_role" == "master1" ]]; then
        hostname_b64=$(echo -n "twonode-master1" | base64)
      elif [[ "$vm_role" == "master2" ]]; then
        hostname_b64=$(echo -n "twonode-master2" | base64)
      else
        hostname_b64=$(echo -n "twonode-arbiter" | base64)
      fi
      cat >> "${IGN_FILE}.tmp" <<EOF

---
# Student ${sid} - ${vm_role^} Ignition
apiVersion: v1
kind: Secret
metadata:
  name: ignition-twonode-${vm_role}
  namespace: ${NAMESPACE_PREFIX}-${sid}
type: Opaque
stringData:
  ignition: |
    {
      "ignition": {
        "version": "3.2.0"
      },
      "passwd": {
        "users": [
          {
            "name": "core",
            "sshAuthorizedKeys": [
              "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC... (replace-with-your-ssh-key)"
            ]
          }
        ]
      },
      "storage": {
        "files": [
          {
            "path": "/etc/hostname",
            "mode": 420,
            "contents": {
              "source": "data:text/plain;charset=utf-8;base64,${hostname_b64}"
            }
          }
        ]
      }
    }
EOF
    done
  done
  mv "${IGN_FILE}.tmp" "$IGN_FILE"
  echo "  ignition-placeholder.yaml"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "=========================================="
echo "VM Generation Complete"
echo "=========================================="
echo ""
echo "Students: ${STUDENT_COUNT}"
echo "Storage:  ${STORAGE_CLASS}"
echo "Running:  false (students start VMs manually)"
echo ""
echo "VMs per student: 7"
echo "  Module 1: rhel-ha-node1, rhel-ha-node2"
echo "  Module 2: microshift-gw-a, microshift-gw-b"
echo "  Module 3: twonode-master1, twonode-master2, twonode-arbiter"
echo ""
echo "Total VMs: $(( STUDENT_COUNT * 7 ))"
