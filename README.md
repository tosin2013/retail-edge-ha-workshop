# 🎯 Retail Edge HA Workshop

[![Deploy GitHub Pages](https://github.com/tosin2013/retail-edge-ha-workshop/actions/workflows/pages.yml/badge.svg)](https://github.com/tosin2013/retail-edge-ha-workshop/actions/workflows/pages.yml)
[![Validate Workshop](https://github.com/tosin2013/retail-edge-ha-workshop/actions/workflows/validate.yml/badge.svg)](https://github.com/tosin2013/retail-edge-ha-workshop/actions/workflows/validate.yml)
[![GitHub Pages](https://img.shields.io/badge/docs-GitHub%20Pages-blue)](https://tosin2013.github.io/retail-edge-ha-workshop/)

> **High Availability Solutions for Two-Node Retail Environments (2026 Edition)**

Welcome to the Retail Edge HA Workshop! This hands-on lab teaches you to design, deploy, and test high-availability systems for heavily constrained retail storefronts using OpenShift Virtualization and User Defined Networks (UDNs).

## 📋 Workshop Overview

This workshop guides you through building three distinct High-Availability architectural paradigms in a simulated "Lab-in-a-Box" environment:

### Learning Modules

1. **Module 1: RHEL HA Add-On (The "Autonomy" Path)**
   - Two RHEL VMs running Pacemaker cluster
   - KubeVirt STONITH fencing (`fence_kubevirt`)
   - Corosync heartbeat over Layer 2 UDN
   - Test failover and recovery

2. **Module 2: MicroShift & VRRP (The "Stateless" Path)**
   - Two MicroShift nodes with Keepalived
   - VRRP virtual IP for Point-of-Sale scanners
   - Layer 2 multicast for VIP failover
   - Zero-downtime failover testing

3. **Module 3: OpenShift Two-Node with Arbiter (The "Enterprise" Path)**
   - Two OpenShift control-plane nodes at retail edge
   - One arbiter node in regional datacenter (simulated)
   - etcd quorum over WAN
   - NetworkPolicy-simulated latency

4. **Module 4: Chaos Testing (The Double-Fault)**
   - CAP theorem limits demonstration
   - Network partition simulation (WAN failure)
   - Simultaneous hardware failure
   - Quorum loss and recovery

## 🏗️ Architecture

This workshop is deployed using a **GitOps-based approach** with:

- **Helm App of Apps Pattern**: Parent ArgoCD Application managing 7 child applications
- **Multi-User Isolation**: Each student gets isolated namespaces with resource quotas
- **OpenShift Virtualization**: 9 VMs per student across 3 HA modules
- **User Defined Networks (UDNs)**: True Layer 2 networking for cluster heartbeat
- **Bookbag Workshop**: Containerized lab guide with embedded instructions

### Component Architecture

```
ArgoCD Parent Application
├── Infrastructure (Sync Wave 0)
│   ├── Student Namespaces (retail-edge-student-XX)
│   ├── Resource Quotas
│   └── Operator Configurations
├── Networking (Sync Wave 1)
│   ├── UDNs for Module 1 (Pacemaker)
│   ├── UDNs for Module 2 (VRRP)
│   ├── UDNs for Module 3 (Two-Node)
│   └── NetworkAttachmentDefinitions
├── RBAC (Sync Wave 1)
│   ├── ClusterRoles
│   ├── RoleBindings
│   └── ServiceAccounts
├── VirtualMachines Module 1 (Sync Wave 2)
│   └── RHEL HA VMs (2 per student)
├── VirtualMachines Module 2 (Sync Wave 2)
│   └── MicroShift VMs (2 per student)
├── VirtualMachines Module 3 (Sync Wave 2)
│   └── OpenShift Two-Node VMs (3 per student: 2 CP + 1 Arbiter)
└── Bookbag (Sync Wave 3)
    ├── Workshop Content Deployment
    ├── Service & Route
    └── Lab Guide

```

## 🚀 Quick Start

### Prerequisites

- OpenShift 4.21+ cluster with:
  - OpenShift GitOps (ArgoCD) operator installed
  - OpenShift Virtualization operator installed
  - OVN-Kubernetes networking (for UDNs)
- `oc` CLI tool installed
- `virtctl` CLI tool installed
- Access to OpenShift cluster with admin privileges

### 1. Configure Git

```bash
git config --global user.name "Tosin Akinosho"
git config --global user.email "takinosh@redhat.com"
```

### 2. Login to OpenShift Cluster

```bash
oc login --token=<your-token> --server=<your-api-server-url>
```

### 3. Deploy Workshop via ArgoCD

```bash
oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-edge-ha-workshop
  namespace: openshift-gitops
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/tosin2013/retail-edge-ha-workshop.git
    targetRevision: main
    path: helm/retail-edge-ha
    helm:
      valueFiles:
        - values.yaml
  destination:
    server: https://kubernetes.default.svc
    namespace: retail-edge-infrastructure
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
EOF
```

### 4. Wait for Deployment

```bash
# Watch ArgoCD sync
argocd app wait retail-edge-ha-workshop --health --timeout 600

# Verify components
oc get namespaces -l workshop=retail-edge-ha
oc get userdefinednetworks --all-namespaces
oc get vms --all-namespaces -l app.kubernetes.io/part-of=retail-edge-ha
```

### 5. Access Workshop

```bash
# Get Bookbag route
BOOKBAG_URL=$(oc get route bookbag -n retail-edge-bookbag -o jsonpath='{.spec.host}')
echo "Workshop URL: https://${BOOKBAG_URL}"
```

## 📁 Repository Structure

```
retail-edge-ha-workshop/
├── README.md                           # This file
├── docs/
│   ├── ADR/                            # Architecture Decision Records
│   │   ├── 0001-helm-app-of-apps.md
│   │   ├── 0002-multi-user-isolation.md
│   │   ├── 0003-vm-networking-udn.md
│   │   ├── 0004-bookbag-delivery.md
│   │   └── 0005-gitops-sync-strategy.md
│   └── deployment-guide.md             # Detailed deployment documentation
├── helm/
│   └── retail-edge-ha/                 # Helm chart (App of Apps)
│       ├── Chart.yaml
│       ├── values.yaml                 # PRIMARY CONFIGURATION FILE
│       └── templates/
│           ├── argocd-app.yaml        # Parent ArgoCD Application
│           ├── namespace.yaml
│           └── apps/                   # Child ArgoCD Applications
│               ├── infrastructure-app.yaml
│               ├── networking-app.yaml
│               ├── rbac-app.yaml
│               ├── vms-module1-app.yaml (TODO)
│               ├── vms-module2-app.yaml (TODO)
│               ├── vms-module3-app.yaml (TODO)
│               └── bookbag-app.yaml
├── manifests/
│   ├── infrastructure/                 # Namespaces, quotas, operators
│   ├── networking/                     # UDNs and NADs
│   ├── vms/                            # VirtualMachine templates
│   ├── rbac/                           # Roles, bindings
│   └── bookbag/                        # Workshop content deployment
├── content/
│   └── workshop/                       # Bookbag workshop content
│       ├── workshop.yaml
│       ├── modules.yaml
│       └── content/                    # AsciiDoc modules
├── agnosticd-integration/              # Agnosticd workload role
│   └── ocp4_workload_retail_edge_ha/
└── scripts/                            # Helper scripts
    ├── generate-student-manifests.sh
    └── validate-deployment.sh
```

## ⚙️ Configuration

All configuration is managed via `helm/retail-edge-ha/values.yaml`:

### Key Configuration Parameters

```yaml
# Student count (1-50)
students:
  count: 5

# OpenShift cluster settings
global:
  clusterDomain: apps.cluster-ntq88.dynamic.redhatworkshops.io
  clusterApiUrl: https://api.cluster-ntq88.dynamic.redhatworkshops.io:6443

# Enable/disable modules
virtualMachines:
  module1:
    enabled: true  # RHEL HA
  module2:
    enabled: true  # MicroShift
  module3:
    enabled: true  # Two-Node OpenShift

# Resource allocations
resourceQuotas:
  limits:
    cpu: "16"
    memory: "32Gi"
    requests.storage: "200Gi"
```

### Customizing for Your Cluster

1. Edit `helm/retail-edge-ha/values.yaml`
2. Update cluster domain and API URL
3. Adjust student count
4. Commit changes to Git
5. ArgoCD automatically syncs updates

## 🧪 Testing & Validation

### Validate Helm Chart

```bash
helm template retail-edge-ha ./helm/retail-edge-ha \
  --values helm/retail-edge-ha/values.yaml \
  --validate
```

### Verify Namespace Creation

```bash
# Expected: 10 namespaces for 5 students (2 per student)
oc get namespaces -l workshop=retail-edge-ha --no-headers | wc -l
```

### Verify UDN Creation

```bash
# Expected: 20 UDNs for 5 students (4 per student: primary + 3 modules)
oc get userdefinednetworks --all-namespaces -l workshop=retail-edge-ha
```

### Verify VM Creation

```bash
# Expected: 45 VMs for 5 students (9 per student)
oc get vms --all-namespaces -l app.kubernetes.io/part-of=retail-edge-ha --no-headers | wc -l
```

## 📚 Documentation

- **[Deployment Guide](docs/deployment-guide.md)**: Step-by-step deployment instructions
- **[Architecture Decision Records](docs/ADR/)**: Documented architectural decisions
- **[Lab Guide](content/workshop/)**: Student-facing workshop content

## 🏆 Workshop Learning Objectives

By completing this workshop, you will:

- ✅ Understand 3 distinct HA architectures for edge deployments
- ✅ Configure Pacemaker clusters with KubeVirt fencing
- ✅ Implement VRRP virtual IP failover with Keepalived
- ✅ Deploy OpenShift two-node clusters with remote arbiters
- ✅ Test CAP theorem limits through chaos engineering
- ✅ Use OpenShift Virtualization for edge simulations
- ✅ Leverage User Defined Networks for Layer 2 connectivity

## 🛠️ Development & Contributing

### Building Bookbag Image

```bash
cd content/workshop
podman build -t quay.io/tosin2013/retail-edge-bookbag:latest .
podman push quay.io/tosin2013/retail-edge-bookbag:latest
```

### Creating ADRs

This project uses the [MCP ADR Analysis Server](https://github.com/tosin2013/mcp-adr-analysis-server) for architectural decision tracking.

```bash
# Create new ADR
npx mcp-adr-analysis-server generate-adr \
  --title "Your Decision Title" \
  --output docs/ADR/000X-your-decision.md
```

### Running Scripts

```bash
# Generate manifests for 50 students
./scripts/generate-student-manifests.sh 50

# Validate deployment
./scripts/validate-deployment.sh
```

## 📊 Resource Requirements

### Per Student

- **CPU**: 18 cores (9 VMs × 2 cores avg)
- **Memory**: 36 GB
- **Storage**: 200 GB (persistent volumes for VM disks)
- **Namespaces**: 2 (workload + UDN)
- **UDNs**: 4 (primary + 3 module networks)
- **VMs**: 9 (2+2+3+2 across modules)

### Maximum Scale (50 Students)

- **CPU**: 900 cores
- **Memory**: 1.8 TB
- **Storage**: 10 TB
- **Namespaces**: 100
- **UDNs**: 200
- **VMs**: 450

## 🔧 Troubleshooting

### ArgoCD Sync Issues

```bash
# Check sync status
argocd app get retail-edge-ha-workshop

# Force sync
argocd app sync retail-edge-ha-workshop --force
```

### VM Not Starting

```bash
# Check VM events
oc describe vm rhel-ha-node1 -n retail-edge-student-01

# Check DataVolume
oc get datavolume -n retail-edge-student-01
```

### UDN Issues

```bash
# Check OVN-Kubernetes
oc get pods -n openshift-ovn-kubernetes

# Describe UDN
oc describe userdefinednetwork pacemaker-net -n retail-edge-student-01-udn
```

## 📝 License

This workshop is provided by Red Hat Field Engineering for educational purposes.

## 👥 Authors

- **Tosin Akinosho** - Initial work - [tosin2013](https://github.com/tosin2013)

## 🙏 Acknowledgments

- Red Hat Edge Infrastructure Team
- OpenShift Virtualization Engineering
- AgnosticD Core Workloads Contributors
- Field-Sourced Content Template Project

## 📞 Support

For questions or issues:
- Open an issue in this repository
- Contact: takinosh@redhat.com

---

**Current Status**: 🚧 **Phase 1: Foundation** (Week 1)

**Implementation Progress**:
- [x] Repository structure created
- [x] Helm chart skeleton (Chart.yaml, values.yaml)
- [x] ArgoCD App of Apps templates
- [x] Infrastructure manifests (namespaces, quotas)
- [ ] Networking manifests (UDNs, NADs) - Week 2
- [ ] VM templates (Modules 1-3) - Week 3-4
- [ ] Bookbag content (Lab guides) - Week 5
- [ ] Full ArgoCD integration - Week 6
- [ ] Agnosticd workload role - Week 7
- [ ] Testing & validation (5, 25, 50 students) - Week 8
