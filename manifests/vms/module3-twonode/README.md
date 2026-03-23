# Module 3: OpenShift Two-Node with Arbiter - VirtualMachines

## Overview

Each student gets **3 VMs** for this module:
- `twonode-master1` (10.103.0.20) - Control plane node 1
- `twonode-master2` (10.103.0.21) - Control plane node 2
- `twonode-arbiter` (10.103.0.22) - etcd arbiter node

This configuration simulates a two-node OpenShift cluster at the retail edge with a remote arbiter for etcd quorum.

## VM Specifications

### Control Plane Nodes (master1, master2)

| Attribute | Value |
|-----------|-------|
| **OS** | Red Hat CoreOS (RHCOS) 9 |
| **CPU** | 4 cores |
| **Memory** | 16Gi |
| **Disk** | 120Gi |
| **Storage Class** | ocs-external-storagecluster-ceph-rbd |
| **Network 1** | default (pod network, masquerade) |
| **Network 2** | twonode-net (UDN, bridge, Layer 2) |

### Arbiter Node

| Attribute | Value |
|-----------|-------|
| **OS** | Red Hat CoreOS (RHCOS) 9 |
| **CPU** | 1 core |
| **Memory** | 2Gi |
| **Disk** | 20Gi |
| **Storage Class** | ocs-external-storagecluster-ceph-rbd |
| **Network 1** | default (pod network, simulates remote datacenter) |
| **Network 2** | twonode-net (UDN, for testing only) |

## Architecture

```
Retail Edge Location              Remote Datacenter (Simulated)
┌─────────────────────────┐      ┌──────────────────────┐
│ twonode-master1         │      │ twonode-arbiter      │
│ 10.103.0.20             │◄────►│ 10.103.0.22          │
│ (etcd member)           │ WAN  │ (etcd arbiter)       │
└─────────────────────────┘      └──────────────────────┘
          │
          │ Layer 2 UDN
          │
┌─────────────────────────┐
│ twonode-master2         │
│ 10.103.0.21             │
│ (etcd member)           │
└─────────────────────────┘
```

## etcd Quorum

- **Total nodes**: 3 (2 control-plane + 1 arbiter)
- **Quorum**: 2 of 3 nodes must be reachable
- **Arbiter role**: Maintains quorum without hosting workloads
- **Failure tolerance**: Can lose 1 node and maintain quorum

## Network Configuration

### eth1 (twonode-net)
- Type: Bridge (Layer 2)
- Purpose: Cluster communication
- IP Assignment: Static via ignition config
  - Master 1: 10.103.0.20/24
  - Master 2: 10.103.0.21/24
  - Arbiter: 10.103.0.22/24

## Initialization

Unlike Modules 1 and 2, OpenShift uses **Ignition** (not cloud-init) for configuration:
- Ignition files are rendered during cluster installation
- VMs boot from RHCOS LiveISO
- Ignition configures networking, hostname, and cluster join

## Files

| File | Purpose | Status |
|------|---------|--------|
| `kustomization.yaml` | Kustomize configuration | ✅ Created |
| `vm-twonode-master1.yaml` | VirtualMachine for master1 (5 students) | ✅ Created |
| `vm-twonode-master2.yaml` | VirtualMachine for master2 (5 students) | ✅ Created |
| `vm-twonode-arbiter.yaml` | VirtualMachine for arbiter (5 students) | ✅ Created |
| `ignition-placeholder.yaml` | Placeholder ignition configs (student-01 only) | ✅ Created |
| `IGNITION-GENERATION.md` | Comprehensive ignition generation guide | ✅ Created |

## Deployment Prerequisites

### 1. RHCOS Image Preparation

Create a shared RHCOS image in the infrastructure namespace:

```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: rhcos-image
  namespace: retail-edge-infrastructure
spec:
  accessModes:
  - ReadOnlyMany
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

# Wait for import to complete
oc get dv rhcos-image -n retail-edge-infrastructure -w
```

### 2. Generate Production Ignition Configs

**IMPORTANT**: The included `ignition-placeholder.yaml` contains minimal configs for testing only.

For production deployment, follow these steps:

1. Review `IGNITION-GENERATION.md` for detailed instructions
2. Install `openshift-install` CLI tool
3. Obtain Red Hat pull secret
4. Run ignition generation for all students:

```bash
# See IGNITION-GENERATION.md for the full script
./generate-ignition-secrets.sh 5
```

This generates proper ignition configs with:
- Cluster certificates
- etcd configuration
- Static IP assignments
- Hostname configuration
- SSH access keys

### 3. Deploy VMs

```bash
# Apply all Module 3 resources
oc apply -k manifests/vms/module3-twonode/

# Start VMs in sequence (master1 first for bootstrap)
virtctl start twonode-master1 -n retail-edge-student-01
sleep 300  # Wait 5 minutes for bootstrap
virtctl start twonode-master2 -n retail-edge-student-01
sleep 120  # Wait 2 minutes
virtctl start twonode-arbiter -n retail-edge-student-01
```

## Cluster Installation Process

### Bootstrap-in-Place (BIP) Flow

1. **master1** boots from RHCOS ISO with ignition config
2. Ignition configures networking, hostname, and starts bootstrap
3. Bootstrap creates temporary control plane
4. **master1** joins the cluster as first control-plane node
5. **master2** boots and joins as second control-plane node
6. **arbiter** boots and joins etcd (no workloads scheduled)
7. Bootstrap components shut down, cluster is operational

### Monitoring Installation

```bash
# Access master1 console
virtctl console twonode-master1 -n retail-edge-student-01

# On master1, watch bootstrap progress
journalctl -u bootkube.service -f

# From your workstation (after kubeconfig is generated)
export KUBECONFIG=~/ocp-twonode-student-01/auth/kubeconfig

# Watch cluster operators
watch oc get co

# Verify nodes
oc get nodes
# Expected output:
# NAME               STATUS   ROLES                  AGE   VERSION
# twonode-master1    Ready    control-plane,worker   10m   v1.27.x
# twonode-master2    Ready    control-plane,worker   5m    v1.27.x
# twonode-arbiter    Ready    control-plane          3m    v1.27.x

# Verify etcd members
oc get etcd cluster -o jsonpath='{.status.members}' | jq
```

## Testing etcd Quorum

### Healthy State (2/3 Quorum)

```bash
# Check etcd health
oc rsh -n openshift-etcd $(oc get pods -n openshift-etcd -l app=etcd -o name | head -1)
etcdctl member list
etcdctl endpoint health --cluster

# Expected: All 3 members healthy
```

### Simulate Node Failure

**Test 1: Lose one control-plane node** (Cluster should remain operational):

```bash
virtctl stop twonode-master2 -n retail-edge-student-01

# Verify cluster still has quorum (2/3: master1 + arbiter)
oc get nodes  # master2 will show NotReady after ~40 seconds
oc get co     # All operators should remain Available

# Restore
virtctl start twonode-master2 -n retail-edge-student-01
```

**Test 2: Lose arbiter** (Cluster should remain operational):

```bash
virtctl stop twonode-arbiter -n retail-edge-student-01

# Verify cluster still has quorum (2/3: master1 + master2)
oc get etcd cluster -o jsonpath='{.status.conditions}' | jq

# Restore
virtctl start twonode-arbiter -n retail-edge-student-01
```

**Test 3: Lose quorum** (Cluster will become read-only):

```bash
# Stop BOTH master2 and arbiter
virtctl stop twonode-master2 -n retail-edge-student-01
virtctl stop twonode-arbiter -n retail-edge-student-01

# Cluster now has only 1/3 members (master1) - NO QUORUM
# API server will reject writes:
oc create namespace test-ns
# Error: etcdserver: request timed out

# Restore quorum
virtctl start twonode-master2 -n retail-edge-student-01
virtctl start twonode-arbiter -n retail-edge-student-01
```

## Troubleshooting

### VMs not booting from ISO

```bash
# Check DataVolume status
oc get dv rhcos-image -n retail-edge-infrastructure

# Verify VM boot order
oc describe vm twonode-master1 -n retail-edge-student-01 | grep -A10 "Boot Order"
```

### Ignition errors

```bash
# Access console during boot
virtctl console twonode-master1 -n retail-edge-student-01

# Check ignition logs
journalctl -u ignition-fetch.service
journalctl -u ignition-disks.service
journalctl -u ignition-files.service
```

### etcd not forming

```bash
# Check etcd pod logs
oc logs -n openshift-etcd etcd-twonode-master1

# Verify network connectivity between nodes
virtctl ssh core@twonode-master1 -n retail-edge-student-01
ping 10.103.0.21  # master2
ping 10.103.0.22  # arbiter
```

### Static IP not configured

```bash
# Check NetworkManager connections
virtctl ssh core@twonode-master1 -n retail-edge-student-01
nmcli con show
ip addr show eth1

# Manually configure if needed
sudo nmcli con mod eth1 ipv4.addresses 10.103.0.20/24
sudo nmcli con mod eth1 ipv4.method manual
sudo nmcli con up eth1
```

## Architecture Notes

- **Arbiter Node**: Runs etcd only, tainted with `NoSchedule` to prevent workloads
- **Split-Brain Prevention**: Requires 2/3 nodes (quorum) for cluster operations
- **Failure Tolerance**: Can lose 1 node without cluster disruption
- **WAN Simulation**: Arbiter uses only `default` network (pod network) to simulate remote datacenter
- **Resource Efficiency**: Arbiter uses minimal resources (1 core, 2Gi RAM)

## Production Considerations

1. **Ignition Configs**: Must be generated per-student with unique cluster certificates
2. **RHCOS Version**: Use same version as your OpenShift cluster for compatibility
3. **Network Latency**: etcd is sensitive to latency; test arbiter connectivity
4. **Storage Performance**: etcd requires low-latency storage (SSD/NVMe recommended)
5. **Cluster Updates**: Two-node clusters require special update procedures

## References

- [OpenShift Two-Node Cluster](https://docs.openshift.com/container-platform/latest/installing/installing_sno/install-sno-installing-sno.html)
- [etcd Arbiter Configuration](https://docs.openshift.com/container-platform/latest/scalability_and_performance/recommended-performance-scale-practices/recommended-etcd-practices.html)
- [Bootstrap-in-Place Installation](https://github.com/openshift/installer/blob/master/docs/user/agent/install_with_agent_and_kvm.md)
- [Ignition v3.2.0 Specification](https://coreos.github.io/ignition/configuration-v3_2/)
