# Fleet Management Infrastructure (RHACM + Edge Manager)

This directory contains the Kubernetes manifests for deploying Red Hat Advanced Cluster Management (RHACM) 2.13+ with Edge Manager capabilities.

## Overview

**RHACM** provides fleet management for Kubernetes/OpenShift clusters and edge devices at scale. In this workshop, students explore fleet management concepts and interact with a real RHACM hub cluster.

### What's Included

- **RHACM Operator Subscription**: Installs the Advanced Cluster Management operator
- **MultiClusterHub CR**: Deploys the RHACM hub cluster components
- **ManagedCluster CRs**: Creates placeholder "spoke clusters" representing student edge sites
- **Edge Manager**: Built-in to RHACM 2.13+ for device fleet management

## Components

### 1. RHACM Operator (`rhacm-operator-subscription.yaml`)

Deploys the RHACM operator in the `open-cluster-management` namespace.

**Sync Wave**: `-2` (before CNV operator)

```yaml
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: advanced-cluster-management
  namespace: open-cluster-management
spec:
  channel: release-2.13
  name: advanced-cluster-management
  source: redhat-operators
```

**Installation Time**: 3-5 minutes

### 2. MultiClusterHub (`multiclusterhub.yaml`)

Creates the RHACM hub cluster with all components enabled.

**Sync Wave**: `0` (after operator is ready)

**Enabled Components**:
- **Console**: RHACM web UI at `https://multicloud-console.apps.<cluster-domain>`
- **Multicluster Engine**: Core multi-cluster management
- **Insights**: Cluster health and recommendations
- **Application UI**: Fleet application lifecycle management
- **Cluster Lifecycle**: Cluster provisioning and management
- **GRC (Governance, Risk, Compliance)**: Policy enforcement
- **Search**: Fleet inventory search

**Installation Time**: 10-15 minutes

**Resource Requirements**:
- **Memory**: 6-8 GB RAM
- **CPU**: 4 cores
- **Storage**: Minimal (metadata only)

### 3. ManagedCluster CRs (`managedclusters.yaml`)

Creates placeholder ManagedCluster resources for each student representing their edge sites.

**Sync Wave**: `1` (after MultiClusterHub is ready)

**Per Student** (3 managed clusters):
- `student-XX-pacemaker` - Module 1: Pacemaker HA cluster
- `student-XX-microshift` - Module 2: MicroShift gateway cluster
- `student-XX-twonode` - Module 3: Two-Node OpenShift cluster

**Labels**:
```yaml
student-id: "01"
module: "module1"
architecture: "pacemaker-ha"
location: "edge-store-001"
```

## Deployment

### Via Helm

RHACM is deployed automatically when `fleetManagement.enabled: true` in `values.yaml`:

```yaml
fleetManagement:
  enabled: true
  rhacm:
    version: "2.13"
    channel: "release-2.13"
    edgeManager:
      enabled: true
```

### Via ArgoCD

The `retail-edge-ha-fleet` ArgoCD application (sync wave `-2`) deploys all resources in this directory:

```bash
oc get application retail-edge-ha-fleet -n openshift-gitops
```

### Manual Deployment

```bash
# Deploy operator
oc apply -f rhacm-operator-subscription.yaml

# Wait for operator
oc get csv -n open-cluster-management -w

# Deploy MultiClusterHub
oc apply -f multiclusterhub.yaml

# Wait for hub (10-15 minutes)
oc get mch -n open-cluster-management -w

# Deploy ManagedCluster CRs
oc apply -f managedclusters.yaml
```

## Validation

### Check RHACM Installation

```bash
# Check MultiClusterHub status
oc get mch multiclusterhub -n open-cluster-management

# Expected output:
# NAME              STATUS    AGE
# multiclusterhub   Running   15m

# Check hub components
oc get pods -n open-cluster-management

# All pods should be Running
```

### Check ManagedClusters

```bash
# List all managed clusters
oc get managedclusters

# Expected output (for 2 students):
# NAME                   HUB ACCEPTED   MANAGED CLUSTER URLS   JOINED   AVAILABLE   AGE
# student-01-pacemaker   true                                  True     Unknown     5m
# student-01-microshift  true                                  True     Unknown     5m
# student-01-twonode     true                                  True     Unknown     5m
# student-02-pacemaker   true                                  True     Unknown     5m
# student-02-microshift  true                                  True     Unknown     5m
# student-02-twonode     true                                  True     Unknown     5m
```

### Access RHACM Console

```bash
# Get console route
oc get route multicloud-console -n open-cluster-management

# URL: https://multicloud-console.apps.<cluster-domain>
```

**Login**: Use your OpenShift credentials

**Student Access**: Students have `open-cluster-management:view` role to explore the console

## Student Experience

Students access RHACM console via environment variables in their Showroom terminals:

```bash
# In student terminal
echo $RHACM_CONSOLE_URL
# Output: https://multicloud-console.apps.cluster-cfz7p.dynamic.redhatworkshops.io

# View their managed clusters
oc get managedclusters -l student-id=01
```

### Module 0: Fleet Management Overview

Students explore:
- RHACM dashboard and inventory
- ManagedCluster list (their 3 edge sites)
- Policy governance concepts
- Fleet application deployment (read-only)

**Lab Time**: 15-20 minutes

## Resource Consumption

**Expected resource usage** (RHACM hub on cluster-cfz7p):

| Component | Memory | CPU | Storage |
|-----------|--------|-----|---------|
| RHACM Operator | 512 Mi | 0.2 | Minimal |
| MultiClusterHub | 6-8 Gi | 3-4 | 5 Gi |
| ManagedCluster CRs | Minimal | Minimal | Minimal |
| **Total** | **~8 GB** | **~4 cores** | **~5 GB** |

**Cluster Capacity Check**:
```bash
oc adm top nodes
# Ensure 8+ GB free RAM across all nodes
```

## Edge Manager Capabilities

RHACM 2.13+ includes **Red Hat Edge Manager** for device fleet management:

- **Device Fleets**: Group edge devices by location, function, or policy
- **Policy-Based Management**: Define desired state for device configurations
- **Automated Rollouts**: Progressive deployment with health checks
- **Real-Time Visibility**: Monitor fleet status and compliance
- **Container Workload Support**: Manage Podman, Docker, and Kubernetes workloads

In this workshop, Edge Manager concepts are introduced in Module 0 but hands-on exercises focus on cluster-level HA patterns (Pacemaker, MicroShift, Two-Node OpenShift).

## Troubleshooting

### MultiClusterHub Not Ready

```bash
# Check MultiClusterHub status
oc describe mch multiclusterhub -n open-cluster-management

# Check operator logs
oc logs -n open-cluster-management \
  $(oc get pods -n open-cluster-management -l name=multiclusterhub-operator -o name) \
  --tail=100
```

### Console Not Accessible

```bash
# Check route
oc get route multicloud-console -n open-cluster-management

# Check console pod
oc get pods -n open-cluster-management -l app=console

# Check pod logs
oc logs -n open-cluster-management \
  $(oc get pods -n open-cluster-management -l app=console -o name) \
  --tail=50
```

### Students Can't Access RHACM

```bash
# Check RBAC
oc get rolebinding -n open-cluster-management | grep student

# Check student user exists
oc get user student-01

# Test as student
oc get managedclusters --as=student-01
```

## References

- [RHACM Documentation](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.13)
- [Edge Manager Guide](https://docs.redhat.com/en/documentation/red_hat_advanced_cluster_management_for_kubernetes/2.13/html-single/edge_manager/index)
- [RHACM Product Page](https://www.redhat.com/en/technologies/management/advanced-cluster-management)
- [Helm-based Applications with RHACM](https://www.redhat.com/en/blog/helm-based-applications-on-red-hat-advanced-cluster-management-and-openshift-gitops)

## Next Steps

1. **Validate deployment**: Run `scripts/validate-workshop-deployment.sh`
2. **Test student access**: Login as student-01 and access RHACM console
3. **Review Module 0**: Check updated fleet management content
4. **Monitor resources**: Watch RHACM memory/CPU consumption during workshop
