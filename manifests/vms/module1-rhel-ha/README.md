# Module 1: RHEL HA with Pacemaker - VirtualMachines

This directory contains VirtualMachine manifests for Module 1: RHEL HA with Pacemaker.

## Overview

Each student gets **2 VMs** for this module:
- `rhel-ha-node1` (10.101.0.20)
- `rhel-ha-node2` (10.101.0.21)

These VMs form a two-node Pacemaker cluster for testing High-Availability scenarios at the retail edge.

## VM Specifications

| Attribute | Value |
|-----------|-------|
| **OS** | RHEL 9 |
| **CPU** | 2 cores |
| **Memory** | 4Gi |
| **Disk** | 30Gi |
| **Storage Class** | ocs-external-storagecluster-ceph-rbd |
| **Network 1** | default (pod network, masquerade) |
| **Network 2** | pacemaker-net (UDN, bridge, Layer 2) |

## Pre-installed Software

Cloud-init automatically installs:
- **pacemaker**: Cluster resource manager
- **pcs**: Pacemaker/Corosync configuration system
- **fence-agents-kubevirt**: STONITH fencing via KubeVirt API
- **corosync**: Cluster communication layer
- **fence-agents-all**: Additional fencing agents

## Network Configuration

### eth0 (default network)
- Type: Masquerade (NAT)
- Purpose: Internet access for package downloads
- DHCP: Automatic

### eth1 (pacemaker-net)
- Type: Bridge (Layer 2)
- Purpose: Corosync heartbeat and cluster communication
- IP Assignment: Static via cloud-init
  - Node 1: 10.101.0.20/24
  - Node 2: 10.101.0.21/24
- Gateway: 10.101.0.1

## Initial Configuration

Cloud-init performs:
1. Set hostname (`rhel-ha-node1` or `rhel-ha-node2`)
2. Configure static IP on eth1 (pacemaker-net)
3. Enable `pcsd` service
4. Set `hacluster` user password to `redhat`
5. Add both nodes to `/etc/hosts`

## Starting VMs

VMs are created with `spec.runStrategy: Manual`. Students must start them manually:

```bash
# Start both VMs
virtctl start rhel-ha-node1 -n retail-edge-student-01
virtctl start rhel-ha-node2 -n retail-edge-student-01

# Check status
oc get vmi -n retail-edge-student-01

# SSH into VM
virtctl ssh cloud-user@rhel-ha-node1 -n retail-edge-student-01
# Password: redhat
```

## Pacemaker Cluster Setup

Once VMs are running, students configure the cluster:

```bash
# SSH into node1
virtctl ssh cloud-user@rhel-ha-node1 -n retail-edge-student-01

# Authenticate nodes
sudo pcs host auth rhel-ha-node1 rhel-ha-node2 -u hacluster -p redhat

# Create cluster
sudo pcs cluster setup storefront-cluster rhel-ha-node1 rhel-ha-node2 --force

# Start cluster
sudo pcs cluster start --all

# Configure two-node quorum
sudo pcs property set expected_votes=2
sudo pcs property set wait_for_all=1
sudo pcs property set no-quorum-policy=stop

# Check status
sudo pcs status
```

## STONITH Fencing Configuration

Configure fence_kubevirt to allow automatic node recovery:

```bash
# Create fence device for node1
sudo pcs stonith create fence-node1 fence_kubevirt \
  namespace=retail-edge-student-01 \
  kubevirt_vm=rhel-ha-node1 \
  pcmk_host_list=rhel-ha-node1

# Create fence device for node2
sudo pcs stonith create fence-node2 fence_kubevirt \
  namespace=retail-edge-student-01 \
  kubevirt_vm=rhel-ha-node2 \
  pcmk_host_list=rhel-ha-node2

# Test fencing (node2 will be forcefully stopped)
sudo pcs stonith fence rhel-ha-node2
```

The `fence_kubevirt` agent uses the KubeVirt API to stop the VM, simulating a power-off.

## Files in This Directory

| File | Purpose |
|------|---------|
| `kustomization.yaml` | Kustomize configuration |
| `vm-rhel-node1.yaml` | VirtualMachine manifests for node1 (all students) |
| `vm-rhel-node2.yaml` | VirtualMachine manifests for node2 (all students) |
| `cloudinit-node1.yaml` | Cloud-init secrets for node1 (all students) |
| `cloudinit-node2.yaml` | Cloud-init secrets for node2 (all students) |

## Generating Manifests for All Students

By default, manifests are created for **5 students**. To generate for all 50:

```bash
cd /home/vpcuser/retail-edge-ha-workshop
./scripts/generate-vm-manifests.sh 50
```

This regenerates all VM and cloud-init manifests with the specified student count.

## Troubleshooting

### VM Won't Start

```bash
# Check DataVolume status
oc get datavolume -n retail-edge-student-01

# Check events
oc describe vm rhel-ha-node1 -n retail-edge-student-01

# Check virt-launcher pod
oc get pods -n retail-edge-student-01
oc logs virt-launcher-rhel-ha-node1-xxxxx -n retail-edge-student-01
```

### Can't Access VM via SSH

```bash
# Check VMI (VirtualMachineInstance) status
oc get vmi rhel-ha-node1 -n retail-edge-student-01

# Access via console (instead of SSH)
virtctl console rhel-ha-node1 -n retail-edge-student-01
# Login: cloud-user / redhat

# Check network interfaces
ip addr show
```

### Pacemaker Cluster Won't Form

```bash
# Check if pcsd is running
sudo systemctl status pcsd

# Check firewall
sudo firewall-cmd --list-all

# Check corosync status
sudo corosync-cfgtool -s

# Check cluster logs
sudo journalctl -u corosync
sudo journalctl -u pacemaker
```

### Fencing Doesn't Work

```bash
# Test fence agent manually
sudo fence_kubevirt \
  --ip=https://api.cluster-cfz7p.dynamic.redhatworkshops.io:6443 \
  --namespace=retail-edge-student-01 \
  --plug=rhel-ha-node2 \
  --action=status

# Check if VM exists in API
oc get vm rhel-ha-node2 -n retail-edge-student-01

# Verify RBAC (ServiceAccount needs permissions)
oc get rolebinding -n retail-edge-student-01
```

## References

- [Pacemaker Documentation](https://clusterlabs.org/pacemaker/doc/)
- [fence_kubevirt Agent](https://github.com/ClusterLabs/fence-agents)
- [ADR-0003: User Defined Networks](../../../docs/ADR/0003-vm-networking-udn.md)
