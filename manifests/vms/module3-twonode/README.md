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
| `vm-twonode-master1.yaml` | VirtualMachine for master1 | 📝 TODO |
| `vm-twonode-master2.yaml` | VirtualMachine for master2 | 📝 TODO |
| `vm-twonode-arbiter.yaml` | VirtualMachine for arbiter | 📝 TODO |
| `ignition-master1.yaml` | Ignition config for master1 | 📝 TODO |
| `ignition-master2.yaml` | Ignition config for master2 | 📝 TODO |
| `ignition-arbiter.yaml` | Ignition config for arbiter | 📝 TODO |

## TODO

1. Generate install-config.yaml for two-node cluster
2. Create ignition files using `openshift-install`
3. Generate VM manifests with `./scripts/generate-vm-manifests.sh 50`

## References

- [OpenShift Two-Node Cluster](https://docs.openshift.com/container-platform/latest/installing/installing_sno/install-sno-installing-sno.html)
- [etcd Arbiter Configuration](https://docs.openshift.com/container-platform/latest/scalability_and_performance/recommended-performance-scale-practices/recommended-etcd-practices.html)
