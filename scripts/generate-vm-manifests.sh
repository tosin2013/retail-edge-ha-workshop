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
# VM base image: RHEL 9 from openshift-virtualization-os-images DataSource
# Edge Manager: If scripts/flightctl-enrollment-config.yaml exists, flightctl-agent
#   enrollment is added to Module 1 and Module 2 cloud-init configs.
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
ENROLLMENT_CONFIG="${SCRIPT_DIR}/flightctl-enrollment-config.yaml"

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

# Check for Edge Manager enrollment config
FLIGHTCTL_ENABLED=false
if [[ -f "$ENROLLMENT_CONFIG" ]]; then
  FLIGHTCTL_ENABLED=true
  echo "Edge Manager enrollment config found: ${ENROLLMENT_CONFIG}"
fi

NAMESPACE_PREFIX="retail-edge-student"
RHEL9_DS_NAME="rhel9"
RHEL9_DS_NAMESPACE="openshift-virtualization-os-images"

echo "=========================================="
echo "Generating VM Manifests"
echo "=========================================="
echo "Student count:   ${STUDENT_COUNT}"
echo "Storage class:   ${STORAGE_CLASS}"
echo "Namespace:       ${NAMESPACE_PREFIX}-XX"
echo "Base image:      RHEL 9 DataSource (${RHEL9_DS_NAMESPACE}/${RHEL9_DS_NAME})"
echo "Edge Manager:    ${FLIGHTCTL_ENABLED}"
echo ""

# =============================================================================
# Helper
# =============================================================================
write_header() {
  local file="$1" header="$2"
  cat > "$file" <<EOF
${header}
EOF
}

# Cloud-init does ALL infrastructure setup. Fleet Manager only delivers
# the status dashboard applications after device enrollment.
#
# Networking: VMs get persistent static IPs from OVN-K via IPAMClaims.
# The UDN uses ipam.lifecycle: Persistent so OVN remembers the IP across
# VM restarts (including STONITH fencing). Pre-created IPAMClaims pin each
# VM to a deterministic IP visible in the OpenShift console (oc get vmi).
#   References:
#     - RHEL HA: static IPs required for Corosync:
#       https://docs.redhat.com/en/documentation/red_hat_enterprise_linux/9/html/configuring_and_managing_high_availability_clusters/assembly_creating-high-availability-cluster-configuring-and-managing-high-availability-clusters
#     - OCP 4.21 UDN API (ipam.lifecycle: Persistent, IPAMClaim):
#       https://docs.redhat.com/en/documentation/openshift_container_platform/4.21/html/network_apis/userdefinednetwork-k8s-ovn-org-v1
FLIGHTCTL_PACKAGES=""
if [[ "$FLIGHTCTL_ENABLED" == "true" ]]; then
  FLIGHTCTL_PACKAGES="      - flightctl-agent"
fi

RHEL_SUB_ENABLED=true

# Per-module repo lists (enabled after registration)
M1_REPOS="rhel-9-for-x86_64-highavailability-rpms,rhel-9-for-x86_64-resilientstorage-rpms,edge-manager-1.0-for-rhel-9-x86_64-rpms"
M2_REPOS="rhocp-4.21-for-rhel-9-x86_64-rpms,fast-datapath-for-rhel-9-x86_64-rpms,edge-manager-1.0-for-rhel-9-x86_64-rpms"

generate_rh_subscription() {
  local repos="$1"
  if [[ "$RHEL_SUB_ENABLED" != "true" ]]; then return; fi
  cat <<ENDOFSUB
    rh_subscription:
      activation-key: 'REPLACE_ACTIVATION_KEY'
      org: 'REPLACE_ORG_ID'
      enable-repo:
ENDOFSUB
  IFS=',' read -ra REPO_ARRAY <<< "$repos"
  for repo in "${REPO_ARRAY[@]}"; do
    echo "        - ${repo}"
  done
}

# Generate Module 1 (Pacemaker) cloud-init write_files + runcmd
# Args: $1=role (node1|node2)
# Static IPs: node1=10.101.0.20, node2=10.101.0.21, VIP=10.101.0.100
# /etc/hosts is written statically — no dynamic discovery needed because
# ipam.mode=Disabled on the UDN ensures IPs never change across reboots.
generate_m1_cloudinit_config() {
  local role="$1"
  local hostname peer_hostname alias_name dashboard_script
  if [[ "$role" == "node1" ]]; then
    hostname="rhel-ha-node1"; peer_hostname="rhel-ha-node2"; alias_name="rhel-ha-node1"
  else
    hostname="rhel-ha-node2"; peer_hostname="rhel-ha-node1"; alias_name="rhel-ha-node2"
  fi
  dashboard_script="ha-status-web.py"

  local ENROLLMENT_INDENT=""
  if [[ "$FLIGHTCTL_ENABLED" == "true" ]]; then
    ENROLLMENT_INDENT=$(sed 's/^/          /' "$ENROLLMENT_CONFIG")
  fi

  # --- write_files ---
  cat <<WFEOF
    write_files:
WFEOF

  if [[ "$FLIGHTCTL_ENABLED" == "true" ]]; then
    cat <<WFEOF
      - path: /etc/flightctl/config.yaml
        owner: root:root
        permissions: '0600'
        content: |
${ENROLLMENT_INDENT}
      - path: /etc/flightctl/labels.yaml
        owner: root:root
        permissions: '0644'
        content: |
          module: pacemaker
          role: ${role}
          alias: ${alias_name}
WFEOF
  fi

  # Static /etc/hosts — IPs never change because UDN IPAM is disabled
  cat <<WFEOF
      - path: /etc/hosts
        owner: root:root
        permissions: '0644'
        append: true
        content: |
          10.101.0.20 rhel-ha-node1
          10.101.0.21 rhel-ha-node2
WFEOF

  if [[ "$FLIGHTCTL_ENABLED" == "true" ]]; then
    cat <<WFEOF
      - path: /etc/systemd/system/ha-status-web.path
        owner: root:root
        permissions: '0644'
        content: |
          [Unit]
          Description=Start HA dashboard when Fleet Manager delivers it
          [Path]
          PathExists=/etc/edge-config/${dashboard_script}
          [Install]
          WantedBy=multi-user.target
WFEOF
  fi

  cat <<WFEOF
      - path: /etc/edge-config/device-role
        owner: root:root
        permissions: '0644'
        content: "${role}"
WFEOF

  # --- runcmd ---
  cat <<RCEOF
    runcmd:
      - hostnamectl set-hostname ${hostname}
      - echo "redhat" | passwd --stdin hacluster
      - systemctl enable --now pcsd
RCEOF

  if [[ "$FLIGHTCTL_ENABLED" == "true" ]]; then
    cat <<RCEOF
      - systemctl enable --now flightctl-agent
      - systemctl daemon-reload
      - systemctl enable --now ha-status-web.path
RCEOF
  fi
}

# Generate Module 2 (MicroShift) cloud-init write_files + runcmd
# Args: $1=role (gw-a|gw-b)
# Static IPs: gw-a=10.102.0.20, gw-b=10.102.0.21, VIP=10.102.0.100
# Same rationale as Module 1 — static IPs on ipam-disabled UDN prevent
# DHCP instability that breaks Keepalived/VRRP peer communication.
generate_m2_cloudinit_config() {
  local role="$1"
  local hostname peer_hostname alias_name keepalived_state keepalived_priority
  local dashboard_script="gateway-status-web.py"
  local VIP="10.102.0.100"

  if [[ "$role" == "gw-a" ]]; then
    hostname="microshift-gw-a"; peer_hostname="microshift-gw-b"; alias_name="microshift-gw-a"
    keepalived_state="MASTER"; keepalived_priority="100"
  else
    hostname="microshift-gw-b"; peer_hostname="microshift-gw-a"; alias_name="microshift-gw-b"
    keepalived_state="BACKUP"; keepalived_priority="90"
  fi

  local ENROLLMENT_INDENT=""
  if [[ "$FLIGHTCTL_ENABLED" == "true" ]]; then
    ENROLLMENT_INDENT=$(sed 's/^/          /' "$ENROLLMENT_CONFIG")
  fi

  # --- write_files ---
  cat <<WFEOF
    write_files:
WFEOF

  if [[ "$FLIGHTCTL_ENABLED" == "true" ]]; then
    cat <<WFEOF
      - path: /etc/flightctl/config.yaml
        owner: root:root
        permissions: '0600'
        content: |
${ENROLLMENT_INDENT}
      - path: /etc/flightctl/labels.yaml
        owner: root:root
        permissions: '0644'
        content: |
          module: microshift
          role: ${role}
          alias: ${alias_name}
WFEOF
  fi

  # Static /etc/hosts — IPs never change because UDN IPAM is disabled
  cat <<WFEOF
      - path: /etc/hosts
        owner: root:root
        permissions: '0644'
        append: true
        content: |
          10.102.0.20 microshift-gw-a
          10.102.0.21 microshift-gw-b
          ${VIP} microshift-vip
      - path: /etc/keepalived/keepalived.conf
        owner: root:root
        permissions: '0644'
        content: |
          vrrp_script check_microshift {
              script "/usr/bin/curl -k -s https://localhost:6443/readyz"
              interval 3
              weight -20
              fall 2
              rise 2
          }
          vrrp_instance MICROSHIFT_VIP {
              state ${keepalived_state}
              interface eth1
              virtual_router_id 1
              priority ${keepalived_priority}
              advert_int 1
              authentication {
                  auth_type PASS
                  auth_pass microshift123
              }
              virtual_ipaddress {
                  ${VIP}/24 dev eth1
              }
              track_script {
                  check_microshift
              }
          }
WFEOF

  if [[ "$FLIGHTCTL_ENABLED" == "true" ]]; then
    cat <<WFEOF
      - path: /etc/systemd/system/gateway-status-web.path
        owner: root:root
        permissions: '0644'
        content: |
          [Unit]
          Description=Start gateway dashboard when Fleet Manager delivers it
          [Path]
          PathExists=/etc/edge-config/${dashboard_script}
          [Install]
          WantedBy=multi-user.target
WFEOF
  fi

  cat <<WFEOF
      - path: /etc/edge-config/device-role
        owner: root:root
        permissions: '0644'
        content: "${role}"
WFEOF

  # --- runcmd ---
  cat <<RCEOF
    runcmd:
      - hostnamectl set-hostname ${hostname}
      - systemctl enable --now firewalld
      - firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16
      - firewall-cmd --permanent --zone=trusted --add-source=169.254.169.1
      - firewall-cmd --permanent --zone=public --add-port=6443/tcp
      - firewall-cmd --permanent --zone=public --add-port=80/tcp
      - firewall-cmd --permanent --zone=public --add-port=443/tcp
      - firewall-cmd --permanent --zone=public --add-port=5353/udp
      - firewall-cmd --permanent --add-protocol=vrrp
      - firewall-cmd --reload
      - systemctl enable --now microshift
      - bash -c 'for i in \$(seq 1 60); do curl -k -s https://localhost:6443/readyz &>/dev/null && break; sleep 5; done'
      - mkdir -p /home/cloud-user/.kube
      - cp /var/lib/microshift/resources/kubeadmin/kubeconfig /home/cloud-user/.kube/config
      - chown -R cloud-user:cloud-user /home/cloud-user/.kube
      - chmod 600 /home/cloud-user/.kube/config
      - systemctl enable --now keepalived
RCEOF

  if [[ "$FLIGHTCTL_ENABLED" == "true" ]]; then
    cat <<RCEOF
      - systemctl enable --now flightctl-agent
      - systemctl daemon-reload
      - systemctl enable --now gateway-status-web.path
RCEOF
  fi
}

# =============================================================================
# MODULE 1: RHEL HA with Pacemaker
# =============================================================================
echo "--- Module 1: RHEL HA ---"

M1_DIR="${REPO_ROOT}/manifests/vms/module1-rhel-ha"

# -- vm-rhel-node1.yaml --
M1_NODE1_VM="${M1_DIR}/vm-rhel-node1.yaml"
write_header "$M1_NODE1_VM" "# VirtualMachine - Module 1: RHEL HA Node 1
# Generated for ${STUDENT_COUNT} students | Storage: ${STORAGE_CLASS}
# Base image: RHEL 9 DataSource"

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
  runStrategy: Manual
  dataVolumeTemplates:
  - apiVersion: cdi.kubevirt.io/v1beta1
    kind: DataVolume
    metadata:
      name: rhel-ha-node1-disk
    spec:
      sourceRef:
        kind: DataSource
        name: ${RHEL9_DS_NAME}
        namespace: ${RHEL9_DS_NAMESPACE}
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
          networkName: pacemaker-net
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
# Generated for ${STUDENT_COUNT} students | Storage: ${STORAGE_CLASS}
# Base image: RHEL 9 DataSource"

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
  runStrategy: Manual
  dataVolumeTemplates:
  - apiVersion: cdi.kubevirt.io/v1beta1
    kind: DataVolume
    metadata:
      name: rhel-ha-node2-disk
    spec:
      sourceRef:
        kind: DataSource
        name: ${RHEL9_DS_NAME}
        namespace: ${RHEL9_DS_NAMESPACE}
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
          networkName: pacemaker-net
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
# Generated for ${STUDENT_COUNT} students | IP via IPAMClaim: 10.101.0.20"

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v sid "%02d" "$i"
  cat >> "$M1_INIT1" <<ENDOFCLOUDINIT

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
ENDOFCLOUDINIT

  generate_rh_subscription "$M1_REPOS" >> "$M1_INIT1"

  cat >> "$M1_INIT1" <<ENDOFPACKAGES
    packages:
      - pacemaker
      - pcs
      - fence-agents-kubevirt
      - corosync
      - fence-agents-all
      - gfs2-utils
      - dlm
      - lvm2-lockd
${FLIGHTCTL_PACKAGES}
ENDOFPACKAGES

  generate_m1_cloudinit_config "node1" >> "$M1_INIT1"
done
echo "  cloudinit-node1.yaml"

# -- cloudinit-node2.yaml --
M1_INIT2="${M1_DIR}/cloudinit-node2.yaml"
write_header "$M1_INIT2" "# Cloud-init - RHEL HA Node 2
# Generated for ${STUDENT_COUNT} students | IP via IPAMClaim: 10.101.0.21"

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v sid "%02d" "$i"
  cat >> "$M1_INIT2" <<ENDOFCLOUDINIT

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
ENDOFCLOUDINIT

  generate_rh_subscription "$M1_REPOS" >> "$M1_INIT2"

  cat >> "$M1_INIT2" <<ENDOFPACKAGES
    packages:
      - pacemaker
      - pcs
      - fence-agents-kubevirt
      - corosync
      - fence-agents-all
      - gfs2-utils
      - dlm
      - lvm2-lockd
${FLIGHTCTL_PACKAGES}
ENDOFPACKAGES

  generate_m1_cloudinit_config "node2" >> "$M1_INIT2"
done
echo "  cloudinit-node2.yaml"

# -- ipamclaims.yaml --
# Pre-created IPAMClaims pin each VM to a known static IP on the UDN.
# OVN-K honours existing claims when lifecycle: Persistent is set.
M1_IPAM="${M1_DIR}/ipamclaims.yaml"
write_header "$M1_IPAM" "# IPAMClaims - Module 1: RHEL HA Pacemaker
# Pre-created claims pin VMs to static IPs on the pacemaker-net UDN.
# Node 1: 10.101.0.20  |  Node 2: 10.101.0.21
# Generated for ${STUDENT_COUNT} students"

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v sid "%02d" "$i"
  cat >> "$M1_IPAM" <<ENDOFIPAM

---
# Student ${sid} - Node 1 IPAMClaim
apiVersion: k8s.cni.cncf.io/v1alpha1
kind: IPAMClaim
metadata:
  name: rhel-ha-node1.pacemaker-net
  namespace: ${NAMESPACE_PREFIX}-${sid}
  labels:
    kubevirt.io/vm: rhel-ha-node1
spec:
  interface: ""
  network: ${NAMESPACE_PREFIX}-${sid}_pacemaker-net
---
# Student ${sid} - Node 2 IPAMClaim
apiVersion: k8s.cni.cncf.io/v1alpha1
kind: IPAMClaim
metadata:
  name: rhel-ha-node2.pacemaker-net
  namespace: ${NAMESPACE_PREFIX}-${sid}
  labels:
    kubevirt.io/vm: rhel-ha-node2
spec:
  interface: ""
  network: ${NAMESPACE_PREFIX}-${sid}_pacemaker-net
ENDOFIPAM
done
echo "  ipamclaims.yaml"

# =============================================================================
# MODULE 2: MicroShift with VRRP
# =============================================================================
echo ""
echo "--- Module 2: MicroShift ---"

M2_DIR="${REPO_ROOT}/manifests/vms/module2-microshift"

# -- vm-microshift-gw-a.yaml --
M2_GWA_VM="${M2_DIR}/vm-microshift-gw-a.yaml"
write_header "$M2_GWA_VM" "# VirtualMachine - Module 2: MicroShift Gateway A
# Generated for ${STUDENT_COUNT} students | Storage: ${STORAGE_CLASS}
# Base image: RHEL 9 DataSource"

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
  runStrategy: Manual
  dataVolumeTemplates:
  - apiVersion: cdi.kubevirt.io/v1beta1
    kind: DataVolume
    metadata:
      name: microshift-gw-a-disk
    spec:
      sourceRef:
        kind: DataSource
        name: ${RHEL9_DS_NAME}
        namespace: ${RHEL9_DS_NAMESPACE}
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
          networkName: microshift-net
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
# Generated for ${STUDENT_COUNT} students | Storage: ${STORAGE_CLASS}
# Base image: RHEL 9 DataSource"

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
  runStrategy: Manual
  dataVolumeTemplates:
  - apiVersion: cdi.kubevirt.io/v1beta1
    kind: DataVolume
    metadata:
      name: microshift-gw-b-disk
    spec:
      sourceRef:
        kind: DataSource
        name: ${RHEL9_DS_NAME}
        namespace: ${RHEL9_DS_NAMESPACE}
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
          networkName: microshift-net
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

# -- cloudinit-gw-a.yaml --
M2_INIT_A="${M2_DIR}/cloudinit-gw-a.yaml"
write_header "$M2_INIT_A" "# Cloud-init - Module 2: MicroShift Gateway A
# Generated for ${STUDENT_COUNT} students | IP via IPAMClaim: 10.102.0.20"

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v sid "%02d" "$i"
  cat >> "$M2_INIT_A" <<ENDOFCLOUDINIT

---
# Student ${sid} - Cloud-init for MicroShift Gateway A
apiVersion: v1
kind: Secret
metadata:
  name: cloudinit-microshift-gw-a
  namespace: ${NAMESPACE_PREFIX}-${sid}
type: Opaque
stringData:
  userdata: |
    #cloud-config
    user: cloud-user
    password: redhat
    chpasswd: { expire: False }
    ssh_pwauth: True
ENDOFCLOUDINIT

  generate_rh_subscription "$M2_REPOS" >> "$M2_INIT_A"

  cat >> "$M2_INIT_A" <<ENDOFPACKAGES
    packages:
      - microshift
      - microshift-selinux
      - microshift-networking
      - keepalived
      - openshift-clients
      - firewalld
${FLIGHTCTL_PACKAGES}
ENDOFPACKAGES

  generate_m2_cloudinit_config "gw-a" >> "$M2_INIT_A"
done
echo "  cloudinit-gw-a.yaml"

# -- cloudinit-gw-b.yaml --
M2_INIT_B="${M2_DIR}/cloudinit-gw-b.yaml"
write_header "$M2_INIT_B" "# Cloud-init - Module 2: MicroShift Gateway B
# Generated for ${STUDENT_COUNT} students | IP via IPAMClaim: 10.102.0.21"

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v sid "%02d" "$i"
  cat >> "$M2_INIT_B" <<ENDOFCLOUDINIT

---
# Student ${sid} - Cloud-init for MicroShift Gateway B
apiVersion: v1
kind: Secret
metadata:
  name: cloudinit-microshift-gw-b
  namespace: ${NAMESPACE_PREFIX}-${sid}
type: Opaque
stringData:
  userdata: |
    #cloud-config
    user: cloud-user
    password: redhat
    chpasswd: { expire: False }
    ssh_pwauth: True
ENDOFCLOUDINIT

  generate_rh_subscription "$M2_REPOS" >> "$M2_INIT_B"

  cat >> "$M2_INIT_B" <<ENDOFPACKAGES
    packages:
      - microshift
      - microshift-selinux
      - microshift-networking
      - keepalived
      - openshift-clients
      - firewalld
${FLIGHTCTL_PACKAGES}
ENDOFPACKAGES

  generate_m2_cloudinit_config "gw-b" >> "$M2_INIT_B"
done
echo "  cloudinit-gw-b.yaml"

# -- ipamclaims.yaml --
M2_IPAM="${M2_DIR}/ipamclaims.yaml"
write_header "$M2_IPAM" "# IPAMClaims - Module 2: MicroShift VRRP
# Pre-created claims pin VMs to static IPs on the microshift-net UDN.
# Gateway A: 10.102.0.20  |  Gateway B: 10.102.0.21
# Generated for ${STUDENT_COUNT} students"

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v sid "%02d" "$i"
  cat >> "$M2_IPAM" <<ENDOFIPAM

---
# Student ${sid} - Gateway A IPAMClaim
apiVersion: k8s.cni.cncf.io/v1alpha1
kind: IPAMClaim
metadata:
  name: microshift-gw-a.microshift-net
  namespace: ${NAMESPACE_PREFIX}-${sid}
  labels:
    kubevirt.io/vm: microshift-gw-a
spec:
  interface: ""
  network: ${NAMESPACE_PREFIX}-${sid}_microshift-net
---
# Student ${sid} - Gateway B IPAMClaim
apiVersion: k8s.cni.cncf.io/v1alpha1
kind: IPAMClaim
metadata:
  name: microshift-gw-b.microshift-net
  namespace: ${NAMESPACE_PREFIX}-${sid}
  labels:
    kubevirt.io/vm: microshift-gw-b
spec:
  interface: ""
  network: ${NAMESPACE_PREFIX}-${sid}_microshift-net
ENDOFIPAM
done
echo "  ipamclaims.yaml"

# =============================================================================
# MODULE 3: Two-Node OpenShift with Arbiter
# =============================================================================
echo ""
echo "--- Module 3: Two-Node OpenShift ---"

M3_DIR="${REPO_ROOT}/manifests/vms/module3-twonode"

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
  runStrategy: Manual
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
          networkName: twonode-net
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

# Ignition placeholders
IGN_FILE="${M3_DIR}/ignition-placeholder.yaml"
if [[ -f "$IGN_FILE" ]]; then
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
echo "Students:      ${STUDENT_COUNT}"
echo "Storage:       ${STORAGE_CLASS}"
echo "Base image:    RHEL 9 (${RHEL9_DS_NAMESPACE}/${RHEL9_DS_NAME})"
echo "Edge Manager:  ${FLIGHTCTL_ENABLED}"
echo "Running:       false (students start VMs manually)"
echo ""
echo "VMs per student: 7"
echo "  Module 1: rhel-ha-node1, rhel-ha-node2"
echo "  Module 2: microshift-gw-a, microshift-gw-b"
echo "  Module 3: twonode-master1, twonode-master2, twonode-arbiter"
echo ""
echo "Total VMs: $(( STUDENT_COUNT * 7 ))"
echo ""
echo "Manifests contain REPLACE_ACTIVATION_KEY / REPLACE_ORG_ID placeholders."
echo "To deploy, run: scripts/apply-vm-manifests.sh"
echo "  (reads credentials from cluster and substitutes at apply time)"
