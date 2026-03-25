# Cluster Requirements - Retail Edge HA Workshop

**Audience:** Cluster administrators planning workshop deployments

This document provides detailed version compatibility matrices, storage backend requirements, network prerequisites, and resource planning guidance.

---

## Table of Contents

1. [OpenShift Version Compatibility](#openshift-version-compatibility)
2. [Operator Requirements](#operator-requirements)
3. [RHEL/RHCOS Version Compatibility](#rhelrhcos-version-compatibility)
4. [Storage Backend Compatibility](#storage-backend-compatibility)
5. [Network Requirements](#network-requirements)
6. [Resource Requirements](#resource-requirements)
7. [Cluster Sizing Calculator](#cluster-sizing-calculator)

---

## OpenShift Version Compatibility

### Tested Versions

| OpenShift Version | Status | Notes |
|-------------------|--------|-------|
| **4.21.x** | ✅ Fully Supported | Recommended version (tested on 4.21.6) |
| **4.22.x** | ✅ Fully Supported | All features working |
| **4.23.x** | ✅ Fully Supported | Latest stable |
| **4.24.x** | ⚠️ Experimental | UDN API changes may require manifest updates |
| **4.20.x** | ⚠️ Limited Support | Missing UDN multicast support |
| **4.19.x and earlier** | ❌ Not Supported | Lacks User Defined Networks feature |

### Minimum Version: OpenShift 4.21.0

**Required Features:**
- User Defined Networks (OVN-Kubernetes Layer 2 topology)
- OpenShift Virtualization 4.16+
- ArgoCD/GitOps Operator 1.12+

### Upgrade Path

Upgrading OpenShift while workshop is deployed:

```bash
# Check current version
oc get clusterversion

# Upgrade to next minor version (4.21 → 4.22)
oc adm upgrade --to=4.22.latest

# Monitor upgrade progress
oc get clusterversion -w
```

**Impact during upgrade:**
- ⚠️ **VMs**: May experience 1-2 second pause during live migration
- ✅ **Showroom**: No impact (pods migrate seamlessly)
- ⚠️ **ArgoCD**: May pause syncs during API server rolling restart

**Recommendation:** Schedule upgrades during workshop off-hours or between cohorts.

---

## Operator Requirements

### OpenShift Virtualization (CNV)

| CNV Operator Version | OpenShift Version | VM Migration | Status |
|----------------------|-------------------|--------------|--------|
| **4.16.x** | 4.21+ | Live Migration | ✅ Recommended |
| **4.17.x** | 4.22+ | Live Migration + Hotplug | ✅ Fully Supported |
| **4.18.x** | 4.23+ | Enhanced Live Migration | ✅ Latest |
| **4.15.x and earlier** | 4.20 | Legacy | ❌ Not Supported |

**Installation:**
```bash
# Via OperatorHub (UI)
1. Navigate to Operators → OperatorHub
2. Search "OpenShift Virtualization"
3. Click Install
4. Select "stable" channel
5. Install to "openshift-cnv" namespace

# Via CLI
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-cnv
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: kubevirt-hyperconverged
  namespace: openshift-cnv
spec:
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  name: kubevirt-hyperconverged
  channel: "stable"
EOF
```

**Verification:**
```bash
oc get csv -n openshift-cnv | grep kubevirt-hyperconverged
# Expected: kubevirt-hyperconverged-operator.v4.16.x   Succeeded
```

### OpenShift GitOps (ArgoCD)

| GitOps Operator Version | ArgoCD Version | App of Apps | Status |
|-------------------------|----------------|-------------|--------|
| **1.12.x** | 2.10.x | ✅ Supported | ✅ Recommended |
| **1.13.x** | 2.11.x | ✅ Supported | ✅ Latest |
| **1.11.x and earlier** | 2.9.x | ✅ Supported | ⚠️ Upgrade Recommended |

**Note:** Workshop deploys ArgoCD automatically if not present. Manual pre-installation not required.

**Verification:**
```bash
oc get csv -n openshift-gitops | grep gitops-operator
# Expected: openshift-gitops-operator.v1.12.x   Succeeded
```

### Operator Version Compatibility Matrix

| Workshop Component | Minimum Operator Version | Recommended Version |
|--------------------|-------------------------|---------------------|
| VirtualMachines | CNV 4.16.0 | CNV 4.17.x |
| User Defined Networks | OVN-Kubernetes (built-in) | N/A (part of OpenShift) |
| ArgoCD Applications | GitOps 1.11.0 | GitOps 1.12.x |
| Showroom BuildConfigs | OpenShift Builds (built-in) | N/A |

---

## RHEL/RHCOS Version Compatibility

### VM Base Images

| Module | OS | Image URL | Tested Version |
|--------|----|-----------| ---------------|
| **Module 1** (Pacemaker) | RHEL 9 | `quay.io/containerdisks/rhel:9.3` | RHEL 9.3, 9.4 |
| **Module 2** (MicroShift) | RHEL 9 | `quay.io/containerdisks/rhel:9.3` | RHEL 9.3, 9.4 |
| **Module 3** (Two-Node OCP) | RHCOS 4.21 | `quay.io/openshift-release-dev/ocp-v4.0-art-dev` | RHCOS 4.21, 4.22 |

**RHEL Version Support:**

| RHEL Version | Pacemaker | MicroShift | Status |
|--------------|-----------|------------|--------|
| **9.3** | ✅ | ✅ | Recommended |
| **9.4** | ✅ | ✅ | Latest |
| **9.2** | ⚠️ | ❌ | MicroShift 4.16+ requires 9.3+ |
| **8.x** | ⚠️ | ❌ | Not tested, use 9.x |

**RHCOS Version Support:**

| RHCOS Version | OpenShift Compatibility | Status |
|---------------|------------------------|--------|
| **4.21.x** | OpenShift 4.21.x | ✅ Recommended |
| **4.22.x** | OpenShift 4.22.x | ✅ Latest |
| **4.20.x** | OpenShift 4.20.x | ⚠️ Limited (UDN issues) |

**Updating VM Images:**

```bash
# Update to RHEL 9.4
vim manifests/vms/module1-rhel-ha/vm-rhel-node1.yaml

# Change image reference
spec:
  template:
    spec:
      volumes:
      - containerDisk:
          image: quay.io/containerdisks/rhel:9.4  # Updated
        name: containerdisk
```

**Impact:** Students must restart VMs to use new image version.

---

## Storage Backend Compatibility

### Storage Class Requirements

**Minimum:** At least one storage class with `ReadWriteOnce` (RWO) support

**Recommended:** Ceph RBD or equivalent high-performance block storage

### Tested Storage Backends

| Storage Backend | Storage Class | RWO | RWX | Performance | Status |
|-----------------|---------------|-----|-----|-------------|--------|
| **Ceph RBD (ODF)** | `ocs-external-storagecluster-ceph-rbd` | ✅ | ❌ | Excellent (500K IOPS) | ✅ Recommended |
| **Ceph FS (ODF)** | `ocs-external-storagecluster-cephfs` | ✅ | ✅ | Good (100K IOPS) | ✅ For shared storage exercises |
| **Local Storage** | `local-storage` | ✅ | ❌ | Excellent (NVMe) | ⚠️ No HA (VM tied to node) |
| **NFS** | `nfs-client` | ✅ | ✅ | Poor (10K IOPS) | ⚠️ Slow VM boot times |
| **AWS EBS (gp3)** | `gp3-csi` | ✅ | ❌ | Good (16K IOPS) | ✅ Supported |
| **Azure Disk** | `managed-csi` | ✅ | ❌ | Good (20K IOPS) | ✅ Supported |
| **GCE PD** | `pd-ssd` | ✅ | ❌ | Good (15K IOPS) | ✅ Supported |

### Storage Performance Requirements

**Per VM:**
- **Minimum**: 3000 IOPS, 50 MB/s throughput
- **Recommended**: 10000 IOPS, 100 MB/s throughput
- **Optimal**: 50000 IOPS, 500 MB/s throughput (NVMe-backed)

**For 50 students (all modules):**
- **Total IOPS**: 150K IOPS minimum, 500K IOPS recommended
- **Total Throughput**: 2.5 GB/s minimum, 5 GB/s recommended
- **Total Capacity**: 10 TiB

**Disk Latency Requirements:**
- **VM boot**: < 500ms latency acceptable
- **etcd (Module 3)**: < 10ms latency required

### Storage Class Selection Logic

Workshop auto-selects storage class in this priority order:

1. Ceph RBD (`ocs-external-storagecluster-ceph-rbd`)
2. Default storage class (cluster-configured)
3. First available storage class

**Override auto-selection:**
```yaml
# In values.yaml
virtualMachines:
  storageClass: "my-custom-storage-class"
```

### Shared Storage (Module 1 GFS2 Exercise)

**Requirements:**
- Storage class with `ReadWriteMany` (RWX) support
- Minimum 10 GiB per student
- Examples: CephFS, NFS, Azure Files

**Verification:**
```bash
oc get storageclass -o json | \
  jq -r '.items[] | select(.metadata.annotations."storageclass.kubernetes.io/is-default-class" == "true") | .metadata.name'
```

---

## Network Requirements

### OVN-Kubernetes CNI

**Required:** Workshop uses User Defined Networks (UDNs) which are OVN-Kubernetes exclusive.

**Verification:**
```bash
oc get network.config.openshift.io cluster -o jsonpath='{.spec.networkType}'
# Expected output: OVNKubernetes
```

**If using different CNI:**
- ❌ **Calico, Cilium, Flannel**: Not compatible (no UDN support)
- Requires cluster rebuild with OVN-Kubernetes

### UDN Feature Requirements

| Feature | Minimum OpenShift Version | Availability |
|---------|--------------------------|--------------|
| **Layer 2 topology** | 4.21.0 | ✅ GA (General Availability) |
| **Multicast support** | 4.21.0 | ✅ GA |
| **Namespace-scoped networks** | 4.21.0 | ✅ GA |
| **VLAN tagging** | 4.22.0 | ⚠️ Tech Preview |

**UDN Configuration:**

The workshop creates 3 UDNs per student:
1. **pacemaker-net** (10.101.0.0/24) - Corosync multicast heartbeat
2. **microshift-net** (10.102.0.0/24) - VRRP virtual IP failover
3. **twonode-net** (10.103.0.0/24) - OpenShift cluster traffic

**Network Isolation:**
- ✅ **Inter-student**: Students cannot communicate across namespaces
- ✅ **Multicast**: Enabled within each UDN (required for Corosync, VRRP)
- ✅ **Layer 2**: VMs receive IPs from static pool (no DHCP)

### Firewall Requirements

**External Access:**
- `quay.io` (VM container images)
- `registry.redhat.io` (RHEL images)
- `github.com` (Showroom content cloning)
- OpenShift cluster API (`api.<cluster>:6443`)
- OpenShift routes (`*.apps.<cluster>`)

**Cluster-Internal:**
- OVN overlay network (Geneve tunnels, UDP 6081)
- Pod-to-pod communication (CNI plugin)
- Service-to-pod communication (kube-proxy)

**Student Access:**
- HTTPS (443) to Showroom routes
- WebSocket (WSS) for terminal access

---

## Resource Requirements

### Per-Student Baseline (Modules 1+2 Only)

| Resource | Module 1 (Pacemaker) | Module 2 (MicroShift) | Total |
|----------|----------------------|----------------------|-------|
| **CPU** | 2 cores × 2 VMs = 4 | 2 cores × 2 VMs = 4 | **8 cores** |
| **Memory** | 4 GiB × 2 VMs = 8 GiB | 4 GiB × 2 VMs = 8 GiB | **16 GiB** |
| **Storage** | 30 GiB × 2 VMs = 60 GiB | 30 GiB × 2 VMs = 60 GiB | **120 GiB** |
| **VMs** | 2 | 2 | **4** |
| **Namespaces** | 1 workload + 1 UDN | (shared) | **2** |

### Per-Student with Module 3 (All Modules)

| Resource | Module 1 | Module 2 | Module 3 (Two-Node) | Total |
|----------|----------|----------|---------------------|-------|
| **CPU** | 4 cores | 4 cores | 3 cores × 3 VMs = 9 cores | **18 cores** |
| **Memory** | 8 GiB | 8 GiB | 6 GiB × 3 VMs = 18 GiB | **36 GiB** |
| **Storage** | 60 GiB | 60 GiB | 40 GiB × 2 + 10 GiB × 1 = 90 GiB | **200 GiB** |
| **VMs** | 2 | 2 | 3 | **9** |

**Note:** Module 3 is disabled by default due to high resource requirements.

### Showroom Overhead (Per Student)

| Component | CPU | Memory | Pods |
|-----------|-----|--------|------|
| showroom (UI) | 100m | 64 MiB | 1 |
| showroom-content (Antora build) | 100m | 64 MiB | 1 |
| showroom-proxy (nginx) | 500m | 256 MiB | 1 |
| showroom-terminal (wetty) | 500m | 256 MiB | 1 |
| **Total per student** | **1.2 cores** | **1 GiB** | **4 pods** |

### Cluster Control Plane Overhead

| Component | CPU | Memory | Notes |
|-----------|-----|--------|-------|
| ArgoCD Server | 1 core | 2 GiB | Scales with app count |
| ArgoCD ApplicationSet Controller | 500m | 512 MiB | For App of Apps pattern |
| OpenShift Virtualization Operators | 2 cores | 4 GiB | virt-controller, virt-api |
| OVN-Kubernetes Controllers | 1 core | 2 GiB | Per node |

**Recommendation:** Add 10-15% overhead to account for cluster services.

---

## Cluster Sizing Calculator

### Small Workshop (5 Students, Modules 1+2)

| Resource | Calculation | Total |
|----------|-------------|-------|
| **CPU** | 5 × 8 cores (VMs) + 5 × 1.2 cores (Showroom) + 5 cores (control plane) | **51 cores** |
| **Memory** | 5 × 16 GiB (VMs) + 5 × 1 GiB (Showroom) + 10 GiB (control plane) | **95 GiB** |
| **Storage** | 5 × 120 GiB | **600 GiB** |

**Recommended Cluster:**
- 3-4 worker nodes
- 16 cores, 32 GiB RAM per node
- 1 TiB total storage

---

### Medium Workshop (25 Students, Modules 1+2)

| Resource | Calculation | Total |
|----------|-------------|-------|
| **CPU** | 25 × 8 cores (VMs) + 25 × 1.2 cores (Showroom) + 10 cores (control plane) | **240 cores** |
| **Memory** | 25 × 16 GiB (VMs) + 25 × 1 GiB (Showroom) + 20 GiB (control plane) | **445 GiB** |
| **Storage** | 25 × 120 GiB | **3 TiB** |

**Recommended Cluster:**
- 6-8 worker nodes
- 32 cores, 64 GiB RAM per node
- 4 TiB total storage

---

### Large Workshop (50 Students, All Modules)

| Resource | Calculation | Total |
|----------|-------------|-------|
| **CPU** | 50 × 18 cores (VMs) + 50 × 1.2 cores (Showroom) + 20 cores (control plane) | **980 cores** |
| **Memory** | 50 × 36 GiB (VMs) + 50 × 1 GiB (Showroom) + 40 GiB (control plane) | **1.9 TiB** |
| **Storage** | 50 × 200 GiB | **10 TiB** |

**Recommended Cluster:**
- 12-15 worker nodes
- 64 cores, 128 GiB RAM per node
- 12 TiB total storage

---

## Cloud Provider Recommendations

### AWS (Elastic Compute Cloud)

| Student Count | Instance Type | Nodes | Total vCPUs | Total RAM |
|---------------|---------------|-------|-------------|-----------|
| **5 students** | m5.4xlarge | 4 | 64 | 256 GiB |
| **25 students** | m5.8xlarge | 8 | 256 | 1 TiB |
| **50 students** | m5.16xlarge | 12 | 768 | 3 TiB |

**Storage:** EBS gp3 volumes (16K IOPS per volume)

### Azure (Virtual Machines)

| Student Count | Instance Type | Nodes | Total vCPUs | Total RAM |
|---------------|---------------|-------|-------------|-----------|
| **5 students** | Standard_D16s_v3 | 4 | 64 | 256 GiB |
| **25 students** | Standard_D32s_v3 | 8 | 256 | 1 TiB |
| **50 students** | Standard_D64s_v3 | 12 | 768 | 3 TiB |

**Storage:** Premium SSD Managed Disks

### Google Cloud Platform (Compute Engine)

| Student Count | Machine Type | Nodes | Total vCPUs | Total RAM |
|---------------|--------------|-------|-------------|-----------|
| **5 students** | n2-standard-16 | 4 | 64 | 256 GiB |
| **25 students** | n2-standard-32 | 8 | 256 | 1 TiB |
| **50 students** | n2-standard-64 | 12 | 768 | 3 TiB |

**Storage:** SSD Persistent Disks

### On-Premises (Bare Metal)

| Student Count | Server Specs | Nodes | Notes |
|---------------|--------------|-------|-------|
| **5 students** | 2× Intel Xeon Gold 6248R (48 cores), 256 GiB RAM, 2 TiB NVMe | 3-4 | Small deployment |
| **25 students** | 2× Intel Xeon Platinum 8280 (56 cores), 512 GiB RAM, 4 TiB NVMe | 6-8 | Medium deployment |
| **50 students** | 2× AMD EPYC 7763 (128 cores), 1 TiB RAM, 8 TiB NVMe | 10-12 | Large deployment |

**Network:** 10 Gbps minimum, 25 Gbps recommended

---

## Validation Checklist

Before deploying workshop, verify:

- [ ] **OpenShift 4.21+** installed
- [ ] **OVN-Kubernetes** CNI configured
- [ ] **OpenShift Virtualization 4.16+** operator installed
- [ ] **Storage class** available (Ceph RBD preferred)
- [ ] **Cluster resources** sufficient for student count (see calculator)
- [ ] **External connectivity** to quay.io, registry.redhat.io, github.com
- [ ] **Cluster admin** credentials available
- [ ] **Cluster domain** and API URL known

**Quick validation script:**
```bash
#!/bin/bash
echo "Checking cluster readiness..."
oc version | grep "Server Version: 4.2[1-9]" && echo "✅ OpenShift 4.21+" || echo "❌ Upgrade required"
oc get network.config.openshift.io cluster -o jsonpath='{.spec.networkType}' | grep "OVNKubernetes" && echo "✅ OVN-K CNI" || echo "❌ Wrong CNI"
oc get csv -n openshift-cnv | grep kubevirt-hyperconverged && echo "✅ CNV installed" || echo "❌ Install CNV"
oc get storageclass && echo "✅ Storage class available" || echo "❌ No storage"
```

---

**Last Updated:** 2025-03-25 | **Tested on:** OpenShift 4.21.6, CNV 4.16.3, GitOps 1.12.1
