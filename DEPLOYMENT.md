# Retail Edge HA Workshop - Deployment Guide

Complete GitOps deployment guide for the Retail Edge High-Availability Workshop.

## Quick Start

### Prerequisites

- OpenShift 4.12+ with:
  - OpenShift Virtualization operator installed
  - OpenShift GitOps (ArgoCD) operator installed
  - Storage class configured (e.g., `ocs-external-storagecluster-ceph-rbd`)
- Cluster admin access
- `oc` CLI installed

### One-Command Deployment

```bash
# Update cluster configuration
export CLUSTER_DOMAIN="apps.your-cluster.com"
export CLUSTER_API="https://api.your-cluster.com:6443"

# Deploy via ArgoCD (recommended)
oc apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-edge-ha
  namespace: openshift-gitops
spec:
  project: default
  source:
    repoURL: https://github.com/tosin2013/retail-edge-ha-workshop.git
    targetRevision: main
    path: helm/retail-edge-ha
    helm:
      valueFiles:
        - values.yaml
      parameters:
        - name: students.count
          value: "5"
        - name: global.clusterDomain
          value: "${CLUSTER_DOMAIN}"
        - name: global.clusterApiUrl
          value: "${CLUSTER_API}"
  destination:
    server: https://kubernetes.default.svc
    namespace: retail-edge-workshop
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
```

This single command deploys the entire workshop infrastructure for 5 students!

---

## What Gets Deployed

### Infrastructure (Sync Wave 0)
- **10 Namespaces**: 5 workload + 5 UDN namespaces per student
- **1 Build Namespace**: For Bookbag image builds
- **ResourceQuotas**: 16 CPU, 32Gi RAM per student
- **RBAC**: ServiceAccounts and RoleBindings

### Networking (Sync Wave 1)
- **15 User Defined Networks** (3 per student):
  - `pacemaker-net` (10.101.0.0/24) - Corosync heartbeat
  - `microshift-net` (10.102.0.0/24) - VRRP failover
  - `twonode-net` (10.103.0.0/24) - etcd cluster traffic

### VirtualMachines (Sync Wave 2)
- **45 VirtualMachines total** (9 per student):
  - **Module 1**: 2 RHEL HA nodes (Pacemaker/Corosync)
  - **Module 2**: 2 MicroShift gateways (VRRP)
  - **Module 3**: 3 OpenShift nodes (2 control-plane + 1 arbiter)

### Workshop Content (Sync Wave 3)
- **BuildConfig**: Builds Bookbag image from GitHub
- **5 Bookbag Deployments**: One per student with personalized lab guide
- **5 Routes**: HTTPS access to workshop dashboards

---

## Deployment Options

### Option 1: ArgoCD (GitOps - Recommended)

**Advantages:**
- Automatic sync from GitHub
- Self-healing if resources deleted
- Audit trail of all changes
- Easy rollback
- Supports 1-50 students

**Steps:**

1. **Clone repository:**
   ```bash
   git clone https://github.com/tosin2013/retail-edge-ha-workshop.git
   cd retail-edge-ha-workshop
   ```

2. **Update configuration:**
   ```bash
   # Edit values.yaml with your cluster details
   vim helm/retail-edge-ha/values.yaml

   # Update these lines:
   # global.clusterDomain: apps.your-cluster.com
   # global.clusterApiUrl: https://api.your-cluster.com:6443
   # students.count: 25  # Adjust student count
   ```

3. **Create ArgoCD Application:**
   ```bash
   oc apply -f helm/retail-edge-ha/templates/argocd-app.yaml
   ```

4. **Monitor deployment:**
   ```bash
   # Via CLI
   oc get applications -n openshift-gitops -w

   # Via UI
   open https://$(oc get route argocd-server -n openshift-gitops -o jsonpath='{.spec.host}')
   ```

5. **Wait for sync** (5-10 minutes):
   - Wave 0: Infrastructure
   - Wave 1: Networking
   - Wave 2: VMs (DataVolume downloads take time)
   - Wave 3: Bookbag

6. **Access workshop:**
   ```bash
   # Get student URLs
   oc get routes -A | grep bookbag

   # Example output:
   # retail-edge-student-01  bookbag  bookbag-retail-edge-student-01.apps...
   ```

### Option 2: Helm Direct Install

**Advantages:**
- Faster initial deployment
- No ArgoCD required
- Good for development/testing

**Steps:**

1. **Install Helm 3:**
   ```bash
   curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
   ```

2. **Deploy:**
   ```bash
   helm install retail-edge-ha ./helm/retail-edge-ha \
     --create-namespace \
     --namespace retail-edge-workshop \
     --set students.count=5 \
     --set global.clusterDomain=apps.your-cluster.com \
     --set global.clusterApiUrl=https://api.your-cluster.com:6443
   ```

3. **Verify:**
   ```bash
   helm list -n retail-edge-workshop
   oc get all -n retail-edge-student-01
   ```

### Option 3: Manual Kustomize

**Advantages:**
- Full control over resources
- Can customize per-module
- Good for troubleshooting

**Steps:**

1. **Generate manifests:**
   ```bash
   # Generate UDNs
   ./scripts/generate-udn-manifests.sh 5

   # Generate VMs
   ./scripts/generate-vm-manifests.sh 5

   # Generate Bookbag
   ./scripts/generate-bookbag-deployments.sh 5
   ```

2. **Apply in order:**
   ```bash
   # Infrastructure
   oc apply -k manifests/infrastructure/namespaces/
   oc apply -k manifests/infrastructure/quotas/

   # Networking
   oc apply -k manifests/networking/udn-module1/
   oc apply -k manifests/networking/udn-module2/
   oc apply -k manifests/networking/udn-module3/

   # VMs
   oc apply -k manifests/vms/module1-rhel-ha/
   oc apply -k manifests/vms/module2-microshift/
   oc apply -k manifests/vms/module3-twonode/

   # Bookbag
   oc apply -f bookbag/deploy/build.yaml
   for i in {01..05}; do
     oc apply -f manifests/bookbag/bookbag-student-${i}.yaml
   done
   ```

---

## Configuration

### Student Count

Supported: **1-50 students**

```yaml
# values.yaml
students:
  count: 25  # Adjust as needed
```

**Resource Requirements** (per student):
- **CPU**: 10 cores (2×2 for Module 1, 2×2 for Module 2, 4+4+1 for Module 3)
- **Memory**: 36Gi (8Gi Module 1, 8Gi Module 2, 16+16+2 Module 3)
- **Storage**: 170Gi (60Gi Module 1, 80Gi Module 2, 260Gi Module 3)

**Total for 25 students:**
- **CPU**: 250 cores
- **Memory**: 900Gi
- **Storage**: 4.25Ti

### Cluster Domain

Update to match your cluster:

```yaml
global:
  clusterDomain: apps.cluster-abc123.example.com
  clusterApiUrl: https://api.cluster-abc123.example.com:6443
```

### Storage Class

Update if using different storage:

```yaml
virtualMachines:
  storageClass: "thin"  # or "gp3", "nfs", etc.
```

### VM Auto-Start

By default, students start VMs manually:

```yaml
virtualMachines:
  autoStart: false  # Set to true for automatic start
```

---

## Post-Deployment

### Build Bookbag Image

Trigger the initial build:

```bash
oc start-build retail-edge-ha-bookbag -n retail-edge-workshop
oc logs -f bc/retail-edge-ha-bookbag -n retail-edge-workshop
```

Wait 3-5 minutes for build to complete.

### Verify Deployments

```bash
# Check all Bookbag pods
oc get pods -A | grep bookbag

# Check student namespaces
oc get namespaces | grep retail-edge-student

# Check VMs
oc get vm -n retail-edge-student-01
```

### Access Workshop

Students navigate to:

```
https://bookbag-retail-edge-student-01.<cluster-domain>/workshop/
```

**Login:**
- Username: `student-01`
- Password: `openshift`

---

## Scaling

### Add More Students

**Via ArgoCD:**
```bash
# Edit Application
oc edit application retail-edge-ha -n openshift-gitops

# Update:
# spec.source.helm.parameters:
# - name: students.count
#   value: "50"  # Changed from 25
```

**Via Helm:**
```bash
helm upgrade retail-edge-ha ./helm/retail-edge-ha \
  --namespace retail-edge-workshop \
  --set students.count=50 \
  --reuse-values
```

### Remove Students

Set `students.count` to a lower number. ArgoCD will prune excess resources if `automated.prune: true`.

---

## Troubleshooting

### VMs Not Starting

**Symptom:** VMs stuck in `Provisioning` state

**Solution:**
```bash
# Check DataVolume status
oc get dv -n retail-edge-student-01

# Check events
oc get events -n retail-edge-student-01 --sort-by='.lastTimestamp'

# Common issue: Storage class not found
oc get sc
```

### Bookbag Build Failing

**Symptom:** BuildConfig errors

**Solution:**
```bash
# Check build logs
oc logs -f bc/retail-edge-ha-bookbag -n retail-edge-workshop

# Common issue: GitHub rate limit
# Wait 5 minutes and retry:
oc start-build retail-edge-ha-bookbag -n retail-edge-workshop
```

### Students Can't Access Workshop

**Symptom:** Route 404 or connection refused

**Solution:**
```bash
# Check Route exists
oc get route bookbag -n retail-edge-student-01

# Check Bookbag pod running
oc get pods -n retail-edge-student-01

# Check image pulled successfully
oc describe pod -n retail-edge-student-01 -l app=bookbag
```

### ArgoCD Out of Sync

**Symptom:** Application status shows "OutOfSync"

**Solution:**
```bash
# Manual sync
argocd app sync retail-edge-ha

# Or via UI:
# Click "Sync" -> "Synchronize"

# Force sync if needed:
argocd app sync retail-edge-ha --force
```

---

## Updating Workshop Content

### Update Lab Guides

1. **Edit AsciiDoc files:**
   ```bash
   vim bookbag/workshop/content/module1-pacemaker.adoc
   ```

2. **Commit changes:**
   ```bash
   git add bookbag/
   git commit -m "Update Module 1 lab guide"
   git push origin main
   ```

3. **Rebuild Bookbag:**
   ```bash
   # ArgoCD auto-triggers build on ConfigChange
   # Or manually:
   oc start-build retail-edge-ha-bookbag -n retail-edge-workshop
   ```

4. **Restart Bookbag pods:**
   ```bash
   oc rollout restart deployment/bookbag -n retail-edge-student-01
   # Repeat for all student namespaces
   ```

### Update Infrastructure

1. **Edit Helm values:**
   ```bash
   vim helm/retail-edge-ha/values.yaml
   ```

2. **Commit changes:**
   ```bash
   git add helm/
   git commit -m "Update VM resources"
   git push origin main
   ```

3. **ArgoCD auto-syncs** (if `automated.selfHeal: true`)

---

## Cleanup

### Remove Workshop

**Via ArgoCD:**
```bash
oc delete application retail-edge-ha -n openshift-gitops
```

**Via Helm:**
```bash
helm uninstall retail-edge-ha -n retail-edge-workshop
```

### Delete Student Namespaces

```bash
for i in {01..50}; do
  oc delete namespace retail-edge-student-${i}
  oc delete namespace retail-edge-student-${i}-udn
done
```

### Delete Build Namespace

```bash
oc delete namespace retail-edge-workshop
```

---

## Production Recommendations

### High Availability

- Deploy on multiple worker nodes (anti-affinity)
- Use persistent storage for Bookbag (PVCs)
- Enable pod disruption budgets
- Configure horizontal pod autoscaling for Bookbag

### Security

- Use NetworkPolicies to isolate student namespaces
- Enable Pod Security Standards
- Rotate student passwords regularly
- Use LDAP/OAuth for authentication instead of static passwords

### Monitoring

- Deploy Prometheus ServiceMonitors for VMs
- Configure AlertManager rules for VM failures
- Enable cluster logging for troubleshooting
- Create Grafana dashboards for resource usage

### Backup

```bash
# Backup Helm values
cp helm/retail-edge-ha/values.yaml values-backup.yaml

# Backup student data (if needed)
for i in {01..50}; do
  oc get all -n retail-edge-student-${i} -o yaml > student-${i}-backup.yaml
done
```

---

## Support

- **Issues**: https://github.com/tosin2013/retail-edge-ha-workshop/issues
- **Discussions**: https://github.com/tosin2013/retail-edge-ha-workshop/discussions
- **Documentation**: https://tosin2013.github.io/retail-edge-ha-workshop/

---

**Version:** 1.0.0
**Last Updated:** March 2025
**Maintainer:** Tosin Akinosho (@tosin2013)
