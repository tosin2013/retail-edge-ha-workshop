# Ignition Configuration Generation Guide

## Overview

Module 3 (Two-Node OpenShift) uses **Ignition** (not cloud-init) for VM initialization. Ignition configs must be generated using the `openshift-install` tool.

## Prerequisites

1. **Download openshift-install**:
   ```bash
   wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-install-linux.tar.gz
   tar xvf openshift-install-linux.tar.gz
   chmod +x openshift-install
   sudo mv openshift-install /usr/local/bin/
   ```

2. **Pull Secret**: Obtain from https://console.redhat.com/openshift/install/pull-secret

3. **SSH Public Key**:
   ```bash
   ssh-keygen -t ed25519 -N '' -f ~/.ssh/ocp-install
   ```

## Installation Steps

### 1. Create install-config.yaml

Create a directory for each student cluster:

```bash
mkdir -p ~/ocp-twonode-student-01
cd ~/ocp-twonode-student-01
```

Create `install-config.yaml`:

```yaml
apiVersion: v1
baseDomain: cluster.local
metadata:
  name: twonode-student-01
networking:
  networkType: OVNKubernetes
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  serviceNetwork:
  - 172.30.0.0/16
  machineNetwork:
  - cidr: 10.103.0.0/24
compute:
- name: worker
  replicas: 0
controlPlane:
  name: master
  replicas: 2
  platform:
    none: {}
platform:
  none: {}
pullSecret: '<your-pull-secret-here>'
sshKey: '<ssh-public-key-here>'
bootstrapInPlace:
  installationDisk: /dev/vda
```

### 2. Generate Manifests

```bash
openshift-install create manifests --dir ~/ocp-twonode-student-01
```

### 3. Configure Arbiter

Create a MachineConfig for the arbiter node to disable workloads:

```bash
cat > ~/ocp-twonode-student-01/manifests/arbiter-machineconfig.yaml <<EOF
apiVersion: machineconfiguration.openshift.io/v1
kind: MachineConfig
metadata:
  labels:
    machineconfiguration.openshift.io/role: master
  name: arbiter-node
spec:
  config:
    ignition:
      version: 3.2.0
    storage:
      files:
      - path: /etc/kubernetes/manifests/arbiter.yaml
        mode: 0644
        contents:
          inline: |
            # Arbiter node configuration
            # This node only runs etcd, no workloads
EOF
```

### 4. Generate Ignition Configs

```bash
openshift-install create ignition-configs --dir ~/ocp-twonode-student-01
```

This creates:
- `bootstrap-in-place-for-live-iso.ign` (for bootstrap)
- `master.ign` (for control-plane nodes)
- `worker.ign` (not used in two-node cluster)

### 5. Customize Ignition for Static IPs

The generated ignition configs use DHCP. For static IPs on `twonode-net`, we need to customize.

**For master1 (10.103.0.20)**:

```bash
cat > ~/ocp-twonode-student-01/master1-static-ip.ign <<'EOF'
{
  "ignition": {
    "version": "3.2.0",
    "config": {
      "merge": [
        {
          "source": "http://webserver.example.com/master.ign"
        }
      ]
    }
  },
  "storage": {
    "files": [
      {
        "path": "/etc/NetworkManager/system-connections/eth1.nmconnection",
        "mode": 384,
        "contents": {
          "source": "data:text/plain;charset=utf-8;base64,<base64-encoded-nmconnection>"
        }
      }
    ]
  },
  "systemd": {
    "units": [
      {
        "name": "configure-network.service",
        "enabled": true,
        "contents": "[Unit]\nDescription=Configure Static IP\nAfter=network.target\n\n[Service]\nType=oneshot\nExecStart=/usr/bin/nmcli con mod eth1 ipv4.addresses 10.103.0.20/24\nExecStart=/usr/bin/nmcli con mod eth1 ipv4.gateway 10.103.0.1\nExecStart=/usr/bin/nmcli con mod eth1 ipv4.method manual\nExecStart=/usr/bin/nmcli con up eth1\n\n[Install]\nWantedBy=multi-user.target"
      }
    ]
  }
}
EOF
```

**Encode to base64 for Kubernetes Secret**:

```bash
cat ~/ocp-twonode-student-01/bootstrap-in-place-for-live-iso.ign | base64 -w0 > master1.ign.b64
```

### 6. Create Kubernetes Secrets

For each student, create ignition Secret manifests:

**manifests/vms/module3-twonode/ignition-master1.yaml**:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: ignition-twonode-master1
  namespace: retail-edge-student-01
type: Opaque
data:
  ignition: <base64-encoded-ignition-from-master1.ign.b64>
```

Repeat for:
- `ignition-twonode-master2.yaml` (with IP 10.103.0.21)
- `ignition-twonode-arbiter.yaml` (with IP 10.103.0.22)

## Automated Generation Script

For convenience, create `generate-ignition-secrets.sh`:

```bash
#!/bin/bash
set -e

STUDENT_COUNT=${1:-5}
PULL_SECRET="<your-pull-secret>"
SSH_KEY=$(cat ~/.ssh/ocp-install.pub)

for i in $(seq -f "%02g" 1 $STUDENT_COUNT); do
  WORKDIR=~/ocp-twonode-student-$i
  mkdir -p $WORKDIR

  # Create install-config.yaml
  cat > $WORKDIR/install-config.yaml <<EOF
apiVersion: v1
baseDomain: cluster.local
metadata:
  name: twonode-student-$i
networking:
  networkType: OVNKubernetes
  clusterNetwork:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  serviceNetwork:
  - 172.30.0.0/16
  machineNetwork:
  - cidr: 10.103.0.0/24
compute:
- name: worker
  replicas: 0
controlPlane:
  name: master
  replicas: 2
  platform:
    none: {}
platform:
  none: {}
pullSecret: '$PULL_SECRET'
sshKey: '$SSH_KEY'
bootstrapInPlace:
  installationDisk: /dev/vda
EOF

  # Backup install-config (it gets consumed)
  cp $WORKDIR/install-config.yaml $WORKDIR/install-config.yaml.bak

  # Generate ignition
  openshift-install create ignition-configs --dir $WORKDIR

  # Encode to base64
  MASTER_IGN=$(cat $WORKDIR/bootstrap-in-place-for-live-iso.ign | base64 -w0)

  # Create Secret manifest for master1
  cat > manifests/vms/module3-twonode/ignition-master1-student-$i.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ignition-twonode-master1
  namespace: retail-edge-student-$i
type: Opaque
data:
  ignition: $MASTER_IGN
EOF

  # Create Secret manifest for master2 (same ignition)
  cat > manifests/vms/module3-twonode/ignition-master2-student-$i.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ignition-twonode-master2
  namespace: retail-edge-student-$i
type: Opaque
data:
  ignition: $MASTER_IGN
EOF

  # Create Secret manifest for arbiter (same ignition)
  cat > manifests/vms/module3-twonode/ignition-arbiter-student-$i.yaml <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ignition-twonode-arbiter
  namespace: retail-edge-student-$i
type: Opaque
data:
  ignition: $MASTER_IGN
EOF

  echo "Generated ignition secrets for student-$i"
done

echo "Ignition generation complete for $STUDENT_COUNT students"
```

**Make executable and run**:

```bash
chmod +x generate-ignition-secrets.sh
./generate-ignition-secrets.sh 5
```

## Important Notes

### RHCOS Image Preparation

The VMs reference `rhcos-image` PVC in `retail-edge-infrastructure` namespace. This must be pre-created:

```bash
cat > rhcos-image-pvc.yaml <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rhcos-image
  namespace: retail-edge-infrastructure
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 10Gi
  storageClassName: ocs-external-storagecluster-ceph-rbd
---
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: rhcos-image
  namespace: retail-edge-infrastructure
spec:
  source:
    http:
      url: "https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest/rhcos-live.x86_64.iso"
  storage:
    resources:
      requests:
        storage: 10Gi
    storageClassName: ocs-external-storagecluster-ceph-rbd
EOF

oc apply -f rhcos-image-pvc.yaml
```

Wait for the image to import:

```bash
oc get dv rhcos-image -n retail-edge-infrastructure -w
# Wait for PHASE: Succeeded
```

### Static IP Configuration

The ignition configs generated above use DHCP. For production, you must:

1. Customize ignition files to include NetworkManager connection profiles
2. Set static IPs for `eth1` interface (twonode-net)
3. Ensure hostname resolution is configured

### Bootstrap Process

OpenShift two-node clusters use "Bootstrap-in-Place" (BIP):

1. **master1** boots first and acts as bootstrap node
2. After master1 completes bootstrap, it becomes a control-plane node
3. **master2** joins the cluster
4. **arbiter** joins only for etcd quorum (no workloads)

### Testing

After VMs start:

```bash
# Check bootstrap progress on master1
virtctl console twonode-master1 -n retail-edge-student-01

# Monitor cluster installation
oc --kubeconfig ~/ocp-twonode-student-01/auth/kubeconfig get co

# Verify nodes
oc get nodes
# Expected: 2 master nodes (Ready), 1 arbiter (Ready, tainted NoSchedule)

# Verify etcd members
oc get etcd -o jsonpath='{range .items[*].status.members[*]}{.name}{"\n"}{end}'
# Expected: twonode-master1, twonode-master2, twonode-arbiter
```

## References

- [OpenShift Two-Node Cluster Documentation](https://docs.openshift.com/container-platform/latest/installing/installing_platform_agnostic/installing-platform-agnostic.html)
- [Bootstrap-in-Place Installation](https://docs.openshift.com/container-platform/latest/installing/installing_sno/install-sno-installing-sno.html)
- [Ignition Configuration Specification](https://coreos.github.io/ignition/configuration-v3_2/)
- [etcd Arbiter Configuration](https://github.com/openshift/enhancements/blob/master/enhancements/etcd/cluster-etcd-operator.md)

## Troubleshooting

### Ignition errors during boot

```bash
# Access VM console
virtctl console twonode-master1 -n retail-edge-student-01

# Check journal for ignition errors
journalctl -u ignition-fetch.service
journalctl -u ignition-disks.service
```

### etcd not forming quorum

```bash
# On master1, check etcd status
oc rsh -n openshift-etcd etcd-twonode-master1
etcdctl member list
etcdctl endpoint health
```

### Network connectivity issues

```bash
# Verify twonode-net attachment
oc describe vmi twonode-master1 -n retail-edge-student-01 | grep -A5 "Network Status"

# Check if eth1 has correct IP
virtctl ssh core@twonode-master1 -n retail-edge-student-01
ip addr show eth1
```
