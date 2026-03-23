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
| `vm-microshift-gw-a.yaml` | VirtualMachine for GW-A (5 students) | ✅ Created |
| `vm-microshift-gw-b.yaml` | VirtualMachine for GW-B (5 students) | ✅ Created |
| `cloudinit-gw-a.yaml` | Cloud-init for GW-A (MASTER, Priority 100) | ✅ Created |
| `cloudinit-gw-b.yaml` | Cloud-init for GW-B (BACKUP, Priority 90) | ✅ Created |

## Deployment

### Prerequisites

1. **UDN Network**: Ensure microshift-net UDN exists in student namespace
   ```bash
   oc get userdefinednetwork -n retail-edge-student-01-udn
   ```

2. **Apply manifests**:
   ```bash
   oc apply -k manifests/vms/module2-microshift/
   ```

3. **Start VMs**:
   ```bash
   virtctl start microshift-gw-a -n retail-edge-student-01
   virtctl start microshift-gw-b -n retail-edge-student-01
   ```

### Testing VRRP Failover

**Initial State** (GW-A is MASTER):
```bash
# On GW-A (should have VIP)
virtctl ssh cloud-user@microshift-gw-a -n retail-edge-student-01
ip addr show eth1 | grep 10.102.0.100
# Should show: inet 10.102.0.100/24 scope global secondary eth1
```

**Simulate Failure** (Stop GW-A):
```bash
virtctl stop microshift-gw-a -n retail-edge-student-01

# On GW-B (should now have VIP)
virtctl ssh cloud-user@microshift-gw-b -n retail-edge-student-01
ip addr show eth1 | grep 10.102.0.100
# VIP should have migrated to GW-B
./check-vrrp.sh
```

**Restore** (Start GW-A):
```bash
virtctl start microshift-gw-a -n retail-edge-student-01

# Wait 30 seconds for VRRP negotiation
# VIP should migrate back to GW-A (higher priority)
```

## Troubleshooting

### VIP not appearing
```bash
# Check Keepalived service
systemctl status keepalived

# Check VRRP logs
journalctl -u keepalived -f

# Verify eth1 has static IP
ip addr show eth1
```

### MicroShift not starting
```bash
# Check MicroShift status
systemctl status microshift

# View logs
journalctl -u microshift -f

# Check firewall
firewall-cmd --list-all
```

### VRRP advertisements not seen
```bash
# Verify Layer 2 connectivity
ping -c 3 10.102.0.20  # GW-A
ping -c 3 10.102.0.21  # GW-B

# Check firewall allows VRRP protocol
firewall-cmd --get-active-zones
firewall-cmd --list-protocols
```

## Architecture Notes

- **Virtual IP**: 10.102.0.100 floats between nodes based on Keepalived priority
- **Multicast**: VRRP uses 224.0.0.18 (requires Layer 2 UDN)
- **Health Check**: Keepalived monitors MicroShift API (https://localhost:6443/readyz)
- **Failover Time**: Typically 3-5 seconds (3 missed advertisements × 1s interval)
- **Authentication**: Simple password auth prevents rogue VRRP instances
