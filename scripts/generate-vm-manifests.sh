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

# Build the flightctl enrollment cloud-init fragments once (reused per VM)
FLIGHTCTL_WRITE_FILES=""
FLIGHTCTL_RUNCMD=""
FLIGHTCTL_PACKAGES=""
if [[ "$FLIGHTCTL_ENABLED" == "true" ]]; then
  # Indent the enrollment config for cloud-init write_files (8-space indent for content inside userdata)
  ENROLLMENT_CONTENT=$(sed 's/^/          /' "$ENROLLMENT_CONFIG")

  FLIGHTCTL_PACKAGES="      - flightctl-agent"

  FLIGHTCTL_WRITE_FILES="      - path: /etc/flightctl/config.yaml
        owner: root:root
        permissions: '0600'
        content: |
${ENROLLMENT_CONTENT}"

  FLIGHTCTL_RUNCMD="      - systemctl enable --now flightctl-agent"
fi

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
  running: false
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
  running: false
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
# Generated for ${STUDENT_COUNT} students | IP: 10.101.0.20"

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
    packages:
      - pacemaker
      - pcs
      - fence-agents-kubevirt
      - corosync
      - fence-agents-all
${FLIGHTCTL_PACKAGES}
ENDOFCLOUDINIT

  # Add write_files section if flightctl is enabled
  if [[ "$FLIGHTCTL_ENABLED" == "true" ]]; then
    cat >> "$M1_INIT1" <<ENDOFWRITEFILES
    write_files:
${FLIGHTCTL_WRITE_FILES}
ENDOFWRITEFILES
  fi

  cat >> "$M1_INIT1" <<ENDOFRUNCMD
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
${FLIGHTCTL_RUNCMD}
ENDOFRUNCMD
done
echo "  cloudinit-node1.yaml"

# -- cloudinit-node2.yaml --
M1_INIT2="${M1_DIR}/cloudinit-node2.yaml"
write_header "$M1_INIT2" "# Cloud-init - RHEL HA Node 2
# Generated for ${STUDENT_COUNT} students | IP: 10.101.0.21"

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
    packages:
      - pacemaker
      - pcs
      - fence-agents-kubevirt
      - corosync
      - fence-agents-all
${FLIGHTCTL_PACKAGES}
ENDOFCLOUDINIT

  if [[ "$FLIGHTCTL_ENABLED" == "true" ]]; then
    cat >> "$M1_INIT2" <<ENDOFWRITEFILES
    write_files:
${FLIGHTCTL_WRITE_FILES}
ENDOFWRITEFILES
  fi

  cat >> "$M1_INIT2" <<ENDOFRUNCMD
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
${FLIGHTCTL_RUNCMD}
ENDOFRUNCMD
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
  running: false
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
  running: false
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
# Generated for ${STUDENT_COUNT} students | IP: 10.102.0.20"

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

    packages:
      - microshift
      - microshift-selinux
      - microshift-networking
      - keepalived
      - openshift-clients
      - firewalld
${FLIGHTCTL_PACKAGES}

    write_files:
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
              state MASTER
              interface eth1
              virtual_router_id 1
              priority 100
              advert_int 1

              authentication {
                  auth_type PASS
                  auth_pass microshift123
              }

              virtual_ipaddress {
                  10.102.0.100/24 dev eth1
              }

              track_script {
                  check_microshift
              }
          }
${FLIGHTCTL_WRITE_FILES}

    runcmd:
      - hostnamectl set-hostname microshift-gw-a

      - nmcli con mod "Wired connection 2" ipv4.addresses 10.102.0.20/24
      - nmcli con mod "Wired connection 2" ipv4.gateway 10.102.0.1
      - nmcli con mod "Wired connection 2" ipv4.method manual
      - nmcli con mod "Wired connection 2" connection.autoconnect yes
      - nmcli con up "Wired connection 2"

      - echo "10.102.0.20 microshift-gw-a" >> /etc/hosts
      - echo "10.102.0.21 microshift-gw-b" >> /etc/hosts
      - echo "10.102.0.100 microshift-vip" >> /etc/hosts

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

      - |
        for i in {1..60}; do
          if curl -k -s https://localhost:6443/readyz &>/dev/null; then
            echo "MicroShift is ready"
            break
          fi
          echo "Waiting for MicroShift... (\$i/60)"
          sleep 5
        done

      - mkdir -p /home/cloud-user/.kube
      - cp /var/lib/microshift/resources/kubeadmin/kubeconfig /home/cloud-user/.kube/config
      - chown -R cloud-user:cloud-user /home/cloud-user/.kube
      - chmod 600 /home/cloud-user/.kube/config

      - systemctl enable --now keepalived

      - |
        cat > /home/cloud-user/test-deployment.sh << 'SCRIPT'
        #!/bin/bash
        oc create deployment nginx --image=nginx --replicas=2
        oc expose deployment nginx --port=80 --type=NodePort
        echo "Test deployment created. Access via: curl http://10.102.0.100:<nodeport>"
        SCRIPT
      - chmod +x /home/cloud-user/test-deployment.sh
      - chown cloud-user:cloud-user /home/cloud-user/test-deployment.sh
${FLIGHTCTL_RUNCMD}
ENDOFCLOUDINIT
done
echo "  cloudinit-gw-a.yaml"

# -- cloudinit-gw-b.yaml --
M2_INIT_B="${M2_DIR}/cloudinit-gw-b.yaml"
write_header "$M2_INIT_B" "# Cloud-init - Module 2: MicroShift Gateway B
# Generated for ${STUDENT_COUNT} students | IP: 10.102.0.21"

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

    packages:
      - microshift
      - microshift-selinux
      - microshift-networking
      - keepalived
      - openshift-clients
      - firewalld
${FLIGHTCTL_PACKAGES}

    write_files:
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
              state BACKUP
              interface eth1
              virtual_router_id 1
              priority 90
              advert_int 1

              authentication {
                  auth_type PASS
                  auth_pass microshift123
              }

              virtual_ipaddress {
                  10.102.0.100/24 dev eth1
              }

              track_script {
                  check_microshift
              }
          }
${FLIGHTCTL_WRITE_FILES}

    runcmd:
      - hostnamectl set-hostname microshift-gw-b

      - nmcli con mod "Wired connection 2" ipv4.addresses 10.102.0.21/24
      - nmcli con mod "Wired connection 2" ipv4.gateway 10.102.0.1
      - nmcli con mod "Wired connection 2" ipv4.method manual
      - nmcli con mod "Wired connection 2" connection.autoconnect yes
      - nmcli con up "Wired connection 2"

      - echo "10.102.0.20 microshift-gw-a" >> /etc/hosts
      - echo "10.102.0.21 microshift-gw-b" >> /etc/hosts
      - echo "10.102.0.100 microshift-vip" >> /etc/hosts

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

      - |
        for i in {1..60}; do
          if curl -k -s https://localhost:6443/readyz &>/dev/null; then
            echo "MicroShift is ready"
            break
          fi
          echo "Waiting for MicroShift... (\$i/60)"
          sleep 5
        done

      - mkdir -p /home/cloud-user/.kube
      - cp /var/lib/microshift/resources/kubeadmin/kubeconfig /home/cloud-user/.kube/config
      - chown -R cloud-user:cloud-user /home/cloud-user/.kube
      - chmod 600 /home/cloud-user/.kube/config

      - systemctl enable --now keepalived

      - |
        cat > /home/cloud-user/test-deployment.sh << 'SCRIPT'
        #!/bin/bash
        oc create deployment nginx --image=nginx --replicas=2
        oc expose deployment nginx --port=80 --type=NodePort
        echo "Test deployment created. Access via: curl http://10.102.0.100:<nodeport>"
        SCRIPT
      - chmod +x /home/cloud-user/test-deployment.sh
      - chown cloud-user:cloud-user /home/cloud-user/test-deployment.sh
${FLIGHTCTL_RUNCMD}
ENDOFCLOUDINIT
done
echo "  cloudinit-gw-b.yaml"

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
