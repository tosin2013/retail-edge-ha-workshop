# Networking Configuration - User Defined Networks (UDNs)

This directory contains User Defined Network (UDN) configurations for the Retail Edge HA Workshop. UDNs provide true Layer 2 networking required for High-Availability protocols.

## Overview

Each student receives **3 isolated Layer 2 networks** (one per module):

| Module | Network Name | CIDR | Purpose |
|--------|--------------|------|---------|
| Module 1 | `pacemaker-net` | 10.101.0.0/24 | Corosync cluster heartbeat |
| Module 2 | `microshift-net` | 10.102.0.0/24 | VRRP virtual IP failover |
| Module 3 | `twonode-net` | 10.103.0.0/24 | Two-node OpenShift cluster |

## Why Layer 2?

### Corosync (Module 1)
- Uses **multicast** (239.255.1.1) for cluster heartbeat
- Requires nodes on same broadcast domain
- Will NOT work over routed (Layer 3) networks

### VRRP (Module 2)
- Sends advertisements to **multicast group** 224.0.0.18
- Uses Virtual Router MAC address for ARP replies
- Requires Layer 2 for ARP and multicast

### etcd (Module 3)
- While etcd works over Layer 3, low-latency Layer 2 reduces heartbeat failures
- Simulates realistic retail edge network topology

## Network Isolation

**Each student's UDNs are completely isolated** despite using the same IP ranges:

```
Student 01: retail-edge-student-01-udn/pacemaker-net (10.101.0.0/24)
Student 02: retail-edge-student-02-udn/pacemaker-net (10.101.0.0/24) ← ISOLATED
Student 03: retail-edge-student-03-udn/pacemaker-net (10.101.0.0/24) ← ISOLATED
```

This is possible because UDNs are **namespace-scoped**. Student 01's VMs on `10.101.0.20` cannot communicate with Student 02's VMs on `10.101.0.20` because they're in different UDN namespaces.

## IP Address Allocation

### Module 1 (Pacemaker) - 10.101.0.0/24

| IP Range | Purpose |
|----------|---------|
| 10.101.0.1 | Gateway (reserved) |
| 10.101.0.2-10 | Infrastructure (reserved) |
| 10.101.0.20 | rhel-ha-node1 |
| 10.101.0.21 | rhel-ha-node2 |

### Module 2 (MicroShift) - 10.102.0.0/24

| IP Range | Purpose |
|----------|---------|
| 10.102.0.1 | Gateway (reserved) |
| 10.102.0.2-10 | Infrastructure (reserved) |
| 10.102.0.20 | microshift-gw-a |
| 10.102.0.21 | microshift-gw-b |
| 10.102.0.100 | **Virtual IP (VRRP)** |

### Module 3 (Two-Node OpenShift) - 10.103.0.0/24

| IP Range | Purpose |
|----------|---------|
| 10.103.0.1 | Gateway (reserved) |
| 10.103.0.2-10 | Infrastructure (reserved) |
| 10.103.0.20 | twonode-master1 |
| 10.103.0.21 | twonode-master2 |
| 10.103.0.22 | twonode-arbiter |

## Directory Structure

```
networking/
├── kustomization.yaml              # Main networking kustomization
├── udn-module1/
│   ├── kustomization.yaml
│   └── udn-pacemaker.yaml          # Pacemaker UDNs (all students)
├── udn-module2/
│   ├── kustomization.yaml
│   └── udn-microshift.yaml         # MicroShift UDNs (all students)
└── udn-module3/
    ├── kustomization.yaml
    └── udn-twonode.yaml            # Two-Node UDNs (all students)
```

## Generating UDNs for All Students

By default, UDN manifests are created for **5 students** (testing). To generate for all 50 students:

```bash
./scripts/generate-udn-manifests.sh 50
```

This script regenerates all three UDN files with the specified student count.

## OVN-Kubernetes Architecture

UDNs use OVN-Kubernetes to provide Layer 2 networking:

1. **Logical Switch**: Each UDN creates an OVN logical switch (Layer 2 domain)
2. **Logical Ports**: Each VM interface gets a logical port on the switch
3. **Geneve Tunnels**: Cross-node traffic uses Geneve encapsulation
4. **MAC Learning**: OVN learns MAC addresses and builds forwarding tables

### Packet Flow Example

```
VM A (10.101.0.20) on Node 1
    ↓
Ethernet frame → OVN logical port
    ↓
Geneve tunnel → OVN logical switch
    ↓
Geneve tunnel → OVN logical port
    ↓
VM B (10.101.0.21) on Node 2
```

## NetworkAttachmentDefinitions

When UDNs are created, OVN-Kubernetes automatically generates **NetworkAttachmentDefinitions (NADs)** that VMs reference:

```yaml
# VM network attachment (UDN in same namespace as VM)
spec:
  networks:
  - name: pacemaker-net
    multus:
      networkName: pacemaker-net
```

The UDN and NAD live in the same namespace as the VMs.

## Validation

### Check UDN Status

```bash
# List all UDNs
oc get userdefinednetworks --all-namespaces

# Check specific student's UDN
oc get udn pacemaker-net -n retail-edge-student-01-udn
oc describe udn pacemaker-net -n retail-edge-student-01-udn
```

### Verify NetworkAttachmentDefinition Created

```bash
# Check NADs in workload namespace
oc get network-attachment-definitions -n retail-edge-student-01
```

### Test Layer 2 Connectivity

```bash
# SSH into VM
virtctl ssh cloud-user@rhel-ha-node1 -n retail-edge-student-01

# Ping broadcast address (Layer 2 test)
ping -b 10.101.0.255

# Check for VRRP multicast (Module 2)
sudo tcpdump -i eth1 -n vrrp
```

## Troubleshooting

### UDN Not Creating

```bash
# Check OVN-Kubernetes pods
oc get pods -n openshift-ovn-kubernetes

# Check UDN events
oc describe udn pacemaker-net -n retail-edge-student-01-udn

# Check logs
oc logs -n openshift-ovn-kubernetes ovnkube-master-XXX -c ovnkube-master
```

### VM Can't Attach to UDN

```bash
# Verify UDN exists
oc get udn -n retail-edge-student-01-udn

# Check VM network configuration
oc describe vm rhel-ha-node1 -n retail-edge-student-01

# Check VMI (VirtualMachineInstance) status
oc describe vmi rhel-ha-node1 -n retail-edge-student-01
```

### No Layer 2 Connectivity

```bash
# Check OVN logical switch
oc exec -n openshift-ovn-kubernetes ovnkube-master-XXX -c ovnkube-master -- \
  ovn-nbctl ls-list | grep pacemaker-net

# Trace packet flow
oc exec -n openshift-ovn-kubernetes ovnkube-master-XXX -c ovnkube-master -- \
  ovn-trace <logical-switch> 'inport=="vm-port" && eth.dst==ff:ff:ff:ff:ff:ff'
```

## Requirements

- **OpenShift 4.14+**: UDNs require OVN-Kubernetes (not OpenShift SDN)
- **OVN-Kubernetes CNI**: Default in OpenShift 4.14+
- **Primary UDN Label**: UDN namespace must have `k8s.ovn.org/primary-user-defined-network=""` label

## References

- [OVN-Kubernetes User Defined Networks](https://docs.openshift.com/container-platform/latest/networking/ovn_kubernetes_network_provider/about-ovn-kubernetes.html)
- [ADR-0003: User Defined Networks for Layer 2 VM Connectivity](../../docs/ADR/0003-vm-networking-udn.md)
- [Multus CNI](https://github.com/k8snetworkplumbingwg/multus-cni)
