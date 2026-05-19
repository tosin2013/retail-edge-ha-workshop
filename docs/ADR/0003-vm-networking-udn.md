# ADR-0003: User Defined Networks for Layer 2 VM Connectivity

## Status

**Accepted** - 2026-03-22

## Context and Problem Statement

The Retail Edge HA Workshop teaches High-Availability architectures that require **true Layer 2 networking** for cluster heartbeat and failover mechanisms:

1. **Module 1 (RHEL HA)**: Corosync heartbeat uses multicast on Layer 2
2. **Module 2 (MicroShift)**: VRRP (Virtual Router Redundancy Protocol) requires Layer 2 for VIP advertisement

Module 3 (Two-Node OpenShift) clusters are provisioned directly on AWS via AgnosticD and imported into RHACM — they run on EC2 instances with AWS networking, so no hub-side Layer 2 is required for Module 3.

**Technical Requirements**:
- Layer 2 broadcast domain (VMs must be on same subnet, no routing)
- Multicast support (for Corosync and VRRP)
- Network isolation between students (student-01's VMs should not see student-02's traffic)
- Multiple isolated networks per student (separate networks for each module)

**Question**: What networking technology should we use to provide Layer 2 connectivity between VirtualMachines while maintaining student isolation?

## Decision Drivers

- **Layer 2 Requirement**: Corosync and VRRP do not work over routed networks
- **Multicast Support**: Required for VRRP and Corosync heartbeat
- **Isolation**: Student networks must be completely separated
- **OpenShift Native**: Must work on standard OpenShift Virtualization
- **Scalability**: Support 50 students × 4 networks = 200 isolated networks

## Considered Options

### Option 1: Default Pod Networking (OVN-Kubernetes SDN)
**Architecture**: VMs get IPs from the pod network (10.128.0.0/14 by default)

**Pros**:
- Simple, no additional configuration
- Automatic IP assignment via CNI

**Cons**:
- ❌ **No Layer 2**: Pod network is Layer 3 routed
- ❌ **No Multicast**: OVN-Kubernetes pod network doesn't support multicast
- ❌ **VRRP Doesn't Work**: Virtual IP failover requires Layer 2
- ❌ **Corosync Fails**: Multicast heartbeat not supported

**Verdict**: Rejected - fundamentally incompatible with HA requirements

### Option 2: Multus with Bridge CNI
**Architecture**: Use Multus to attach additional bridge networks to VMs

**Example**:
```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: pacemaker-bridge
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "bridge",
      "bridge": "br-pacemaker",
      "ipam": {
        "type": "host-local",
        "subnet": "10.101.0.0/24"
      }
    }
```

**Pros**:
- ✅ Layer 2 broadcast domain
- ✅ Multicast support
- Well-established pattern

**Cons**:
- ⚠️ **Node-Local Only**: Bridge only exists on one node; VMs on different nodes can't communicate
- ⚠️ **No Cross-Node**: Requires all student VMs scheduled to same node (anti-pattern)
- ⚠️ **VLAN Complexity**: Would need VLAN trunking for cross-node Layer 2

**Verdict**: Rejected - doesn't work across nodes without extensive network configuration

### Option 3: Multus with OVN Secondary Networks (Localnet)
**Architecture**: Use OVN localnet provider with physical network mapping

**Pros**:
- ✅ Cross-node Layer 2
- ✅ Multicast support via physical network

**Cons**:
- ❌ **Physical Network Dependency**: Requires VLAN configuration on physical switches
- ❌ **Cluster Admin Coordination**: Cannot be self-service
- ❌ **Not Portable**: Tied to specific datacenter infrastructure

**Verdict**: Rejected - requires physical network changes (not "Lab-in-a-Box")

### Option 4: User Defined Networks (UDNs) - Layer 2 Topology (SELECTED)
**Architecture**: Use OVN-Kubernetes User Defined Networks with Layer 2 topology

**Example**:
```yaml
apiVersion: k8s.ovn.org/v1
kind: UserDefinedNetwork
metadata:
  name: pacemaker-net
  namespace: retail-edge-student-01-udn
spec:
  topology: Layer2
  layer2:
    role: Primary
    subnets:
    - cidr: 10.101.0.0/24
      gateway: 10.101.0.1
```

**Pros**:
- ✅ **True Layer 2**: OVN creates virtual Layer 2 broadcast domain
- ✅ **Multicast Support**: Enabled by default in Layer 2 topology
- ✅ **Cross-Node**: Works across OpenShift nodes via Geneve tunnels
- ✅ **Namespace-Scoped**: Automatic isolation (student-01's UDN separate from student-02)
- ✅ **OpenShift Native**: No external dependencies
- ✅ **Self-Service**: Students can create UDNs in their namespace
- ✅ **No Physical Network Changes**: Pure software-defined networking

**Cons**:
- ⚠️ **OpenShift 4.14+ Required**: UDNs are new feature
- ⚠️ **OVN-Kubernetes Only**: Doesn't work with OpenShift SDN (deprecated anyway)
- ⚠️ **Learning Curve**: New technology for many operators

**Verdict**: Selected - meets all requirements with OpenShift-native technology

## Decision

**We will use User Defined Networks (UDNs) with Layer 2 topology** for all module networking.

### Implementation

**Network Architecture per Student**:
```
Student 01:
├── retail-edge-student-01-udn (namespace)
│   ├── pacemaker-net (UDN, 10.101.0.0/24)     # Module 1
│   └── microshift-net (UDN, 10.102.0.0/24)    # Module 2

Student 02:
├── retail-edge-student-02-udn (namespace)
│   ├── pacemaker-net (UDN, 10.101.0.0/24)     # Same CIDR, different namespace = isolated
│   └── microshift-net (UDN, 10.102.0.0/24)
```

**UDN Definition (Module 1 - Pacemaker)**:
```yaml
apiVersion: k8s.ovn.org/v1
kind: UserDefinedNetwork
metadata:
  name: pacemaker-net
  namespace: retail-edge-student-01-udn
  labels:
    workshop: retail-edge-ha
    module: module1
    student-id: "01"
spec:
  topology: Layer2
  layer2:
    role: Primary
    subnets:
    - cidr: 10.101.0.0/24
      gateway: 10.101.0.1
      excludeSubnets:
      - 10.101.0.1/32  # Gateway
      - 10.101.0.2-10.101.0.10  # Reserved
```

**VM Attachment to UDN**:
```yaml
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: rhel-ha-node1
  namespace: retail-edge-student-01
spec:
  template:
    spec:
      domain:
        devices:
          interfaces:
          - name: default
            masquerade: {}      # Standard pod network
          - name: pacemaker-net
            bridge: {}          # UDN Layer 2 network
      networks:
      - name: default
        pod: {}
      - name: pacemaker-net
        multus:
          networkName: retail-edge-student-01-udn/pacemaker-net
```

**IP Assignment**:
- **Static IPs**: Configured via cloud-init
- **No DHCP**: UDNs don't provide DHCP server (by design)
- **Per-Student Allocation**:
  - Module 1 (Pacemaker): 10.101.0.20-21 (2 VMs)
  - Module 2 (MicroShift): 10.102.0.20-21 (2 VMs) + 10.102.0.100 (VIP)
  - Module 3: AWS-provisioned clusters — no hub UDN

## Consequences

### Positive

✅ **Authentic HA Testing**: Corosync and VRRP work exactly as in production retail environments
✅ **Network Isolation**: Each student's UDN is completely isolated (same CIDR doesn't conflict)
✅ **Multicast Support**: VRRP advertisements and Corosync heartbeats function correctly
✅ **Cross-Node Transparent**: VMs on different nodes communicate via Geneve tunnels
✅ **No Physical Network Changes**: Pure software-defined networking, portable to any OpenShift cluster
✅ **Realistic Edge Simulation**: Mirrors real retail edge Layer 2 switch behavior

### Negative

❌ **OpenShift 4.14+ Required**: Cannot use older OpenShift versions
   - *Mitigation*: Document minimum version requirement clearly
   - *Impact*: Most production clusters are 4.14+ by 2026

❌ **Static IP Management**: VMs need static IPs configured via cloud-init
   - *Mitigation*: Cloud-init templates with per-student IP allocation
   - *Impact*: Adds complexity to VM templates

❌ **Troubleshooting Complexity**: Network issues require understanding OVN
   - *Mitigation*: Provide troubleshooting guide with common commands
   - *Mitigation*: Include `ovn-trace` examples for debugging

❌ **No DHCP**: Students cannot rely on automatic IP assignment
   - *Mitigation*: Document IP addressing scheme clearly
   - *Impact*: More educational (students learn static IP configuration)

### Neutral

⚖️ **OVN-Kubernetes Dependency**: Requires OVN-Kubernetes CNI (not OpenShift SDN)
   - OpenShift SDN is deprecated; OVN-Kubernetes is the standard

⚖️ **Namespace Requirement**: UDNs must be in a namespace with specific labels
   - This is why we have the dual-namespace pattern (ADR-0002)

## Validation

**Test Cases**:

1. **Layer 2 Broadcast Test**:
   ```bash
   # From rhel-ha-node1
   ping -b 10.101.0.255  # Broadcast address
   # Expected: Both VMs respond
   ```

2. **Multicast Test (VRRP)**:
   ```bash
   # On microshift-gw-a
   tcpdump -i eth1 vrrp
   # Expected: See VRRP advertisements to 224.0.0.18
   ```

3. **Isolation Test**:
   ```bash
   # From student-01's VM
   ping 10.101.0.20  # Student-02's VM (same IP, different UDN)
   # Expected: No response (isolated UDN)
   ```

4. **Cross-Node Test**:
   ```bash
   # Schedule VMs on different nodes
   oc patch vm rhel-ha-node1 -n retail-edge-student-01 --type=merge -p '
     spec:
       template:
         spec:
           nodeSelector:
             kubernetes.io/hostname: worker-01'

   oc patch vm rhel-ha-node2 -n retail-edge-student-01 --type=merge -p '
     spec:
       template:
         spec:
           nodeSelector:
             kubernetes.io/hostname: worker-02'

   # Start VMs and ping
   virtctl start rhel-ha-node1 rhel-ha-node2 -n retail-edge-student-01
   virtctl ssh cloud-user@rhel-ha-node1 -n retail-edge-student-01
   ping 10.101.0.21  # node2's IP
   # Expected: Successful ping across nodes
   ```

## Technical Deep Dive

### How UDNs Provide Layer 2

**OVN Architecture**:
1. **Logical Switch**: UDN creates an OVN logical switch (Layer 2 domain)
2. **Logical Ports**: Each VM interface gets a logical port
3. **Geneve Tunnels**: OVN uses Geneve encapsulation for cross-node traffic
4. **MAC Learning**: OVN learns MAC addresses and builds forwarding tables

**Packet Flow**:
```
VM A (10.101.0.20) → Ethernet frame → OVN logical port →
Geneve tunnel → OVN logical switch → Geneve tunnel →
OVN logical port → VM B (10.101.0.21)
```

### Why Layer 2 Matters for HA

**Corosync (Module 1)**:
- Uses multicast (239.255.1.1 by default) for heartbeat
- Requires nodes to be on same broadcast domain
- Will not work over routed networks

**VRRP (Module 2)**:
- Sends advertisements to multicast group 224.0.0.18
- Uses Virtual Router MAC address (00:00:5e:00:01:{VRID})
- ARP replies for VIP must come from master node
- Requires Layer 2 for ARP and multicast

## Troubleshooting Guide

**Check UDN Status**:
```bash
oc get userdefinednetwork pacemaker-net -n retail-edge-student-01-udn
oc describe userdefinednetwork pacemaker-net -n retail-edge-student-01-udn
```

**Verify NetworkAttachmentDefinition Created**:
```bash
oc get network-attachment-definitions -n retail-edge-student-01
```

**Debug VM Network Attachment**:
```bash
oc describe vmi rhel-ha-node1 -n retail-edge-student-01
# Check: Status → Interfaces → pacemaker-net
```

**Trace Packet Flow with OVN**:
```bash
# Get logical switch name
oc exec -n openshift-ovn-kubernetes ovnkube-master-XXX -c ovnkube-master -- \
  ovn-nbctl ls-list | grep pacemaker-net

# Trace packet
oc exec -n openshift-ovn-kubernetes ovnkube-master-XXX -c ovnkube-master -- \
  ovn-trace <logical-switch> 'inport=="vm-port" && eth.dst==ff:ff:ff:ff:ff:ff'
```

## Alternative Technologies Rejected

### SR-IOV
**Reason**: Requires specific hardware (NICs with SR-IOV support). Not portable.

### MacVLAN
**Reason**: Requires promiscuous mode on node NICs. Security risk and not supported in many cloud environments.

### Flannel Host-GW
**Reason**: Layer 3 only, no multicast support.

## Notes

- UDNs are a Technology Preview feature in OpenShift 4.14, GA in 4.17+
- Future enhancement: IPv6 dual-stack UDNs for modern edge deployments
- Consider MTU implications (Geneve adds 50-100 bytes overhead)

## Related ADRs

- **ADR-0002**: Multi-User Namespace Isolation (explains dual-namespace requirement)
- **ADR-0001**: Helm-based App of Apps Pattern (explains UDN template generation)

## References

- [OVN-Kubernetes User Defined Networks](https://docs.openshift.com/container-platform/latest/networking/ovn_kubernetes_network_provider/about-ovn-kubernetes.html)
- [Multus CNI](https://github.com/k8snetworkplumbingwg/multus-cni)
- [VRRP RFC 5798](https://datatracker.ietf.org/doc/html/rfc5798)
- [Corosync Documentation](https://corosync.github.io/corosync/)

---

**Author**: Tosin Akinosho
**Date**: 2026-03-22
**Reviewers**: Networking Team, Field Engineering Team
**Supersedes**: None
**Superseded By**: None
