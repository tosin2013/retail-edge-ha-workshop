# Module 2: MicroShift with VRRP - VirtualMachines

## Overview

Each student gets **2 VMs** for this module:
- `microshift-gw-a` (10.102.0.20)
- `microshift-gw-b` (10.102.0.21)
- Virtual IP: 10.102.0.100 (managed by VRRP)

These VMs run single-node MicroShift instances with Keepalived for VRRP failover.

## VM Specifications

| Attribute | Value |
|-----------|-------|
| **OS** | RHEL 9 Stream with MicroShift |
| **CPU** | 2 cores |
| **Memory** | 4Gi |
| **Disk** | 40Gi |
| **Storage Class** | ocs-external-storagecluster-ceph-rbd |
| **Network 1** | default (pod network, masquerade) |
| **Network 2** | microshift-net (UDN, bridge, Layer 2) |

## Pre-installed Software

Cloud-init automatically installs:
- **microshift**: Lightweight Kubernetes (subset of OpenShift)
- **microshift-selinux**: SELinux policies
- **microshift-networking**: CNI and networking components
- **keepalived**: VRRP daemon for VIP management

## Network Configuration

### eth1 (microshift-net)
- Type: Bridge (Layer 2)
- Purpose: VRRP virtual IP failover
- IP Assignment: Static via cloud-init
  - Gateway A: 10.102.0.20/24
  - Gateway B: 10.102.0.21/24
  - Virtual IP: 10.102.0.100 (floats between nodes)

## VRRP Configuration

Keepalived manages the Virtual IP (10.102.0.100):
- **Priority**: GW-A = 100 (master), GW-B = 90 (backup)
- **VRID**: 1 (Virtual Router ID)
- **Advertisements**: Sent to multicast 224.0.0.18
- **Health Check**: Monitors MicroShift API (port 6443)

## Files

| File | Purpose | Status |
|------|---------|--------|
| `kustomization.yaml` | Kustomize configuration | ✅ Created |
| `vm-microshift-gw-a.yaml` | VirtualMachine for GW-A | 📝 TODO |
| `vm-microshift-gw-b.yaml` | VirtualMachine for GW-B | 📝 TODO |
| `cloudinit-gw-a.yaml` | Cloud-init for GW-A | 📝 TODO |
| `cloudinit-gw-b.yaml` | Cloud-init for GW-B | 📝 TODO |

## TODO

Run `./scripts/generate-vm-manifests.sh 50` to generate manifests for all students.
