# Operations Guide - Retail Edge HA Workshop

**Audience:** Workshop operators, cluster administrators, RHPDS catalog maintainers

This guide covers production operations for deployed workshops: monitoring, scaling, maintenance, backup/restore, security, and incident response.

---

## Table of Contents

1. [Monitoring](#monitoring)
2. [Scaling](#scaling)
3. [Maintenance](#maintenance)
4. [Backup and Restore](#backup-and-restore)
5. [Security](#security)
6. [Incident Response](#incident-response)
7. [Performance Tuning](#performance-tuning)

---

## Monitoring

### ArgoCD Application Health

Monitor GitOps deployment status:

```bash
# Check all applications
oc get applications -n retail-edge-ha-gitops

# Watch for sync failures
oc get applications -n retail-edge-ha-gitops -o json | \
  jq -r '.items[] | select(.status.health.status != "Healthy") | .metadata.name'

# Check specific application details
oc describe application retail-edge-ha-showroom-01 -n retail-edge-ha-gitops
```

**Health indicators:**
- ✅ **Healthy + Synced**: Application deployed successfully
- ⚠️ **Progressing**: Deployment in progress (normal for first 5-10 min)
- ❌ **Degraded**: Pods failing, resources missing
- ⚠️ **OutOfSync**: Cluster state doesn't match Git

**Alerting threshold:** If applications remain "Progressing" > 15 minutes, investigate.

### VM Status Monitoring

Track virtual machine deployment and health:

```bash
# Count VMs across all students
oc get vm -A | grep retail-edge-student | wc -l
# Expected: (students × modules) - Module1: 2, Module2: 2, Module3: 3

# Check for VMs in error state
oc get vm -A -o json | \
  jq -r '.items[] | select(.status.printableStatus != "Running" and .status.printableStatus != "Stopped") | "\(.metadata.namespace)/\(.metadata.name): \(.status.printableStatus)"'

# Monitor VMIs (running instances)
oc get vmi -A | grep retail-edge-student
```

**Health indicators:**
- ✅ **Stopped**: Normal (VMs are pre-deployed in stopped state)
- ✅ **Running**: VM started by student
- ⚠️ **Pending**: Waiting for resources (check DataVolume status)
- ❌ **Failed**: VM crash, check virt-launcher logs

### Showroom Pod Health

Monitor workshop lab guide availability:

```bash
# Check Showroom pods across all students
for i in $(seq -f "%02g" 1 10); do
  echo "=== Student $i ==="
  oc get pods -n showroom-student-$i --no-headers | \
    awk '{print $1, $3}' | grep -v "Running\|Completed" || echo "All pods running"
done

# Check Showroom build status
oc get builds -A | grep showroom
```

**Health indicators:**
- ✅ **Running (4/4 pods)**: Fully operational
- ⚠️ **ImagePullBackOff**: Check build logs, possible GitHub rate limit
- ❌ **CrashLoopBackOff**: Check pod logs for errors

### Resource Utilization

Monitor cluster capacity:

```bash
# Overall cluster resource usage
oc adm top nodes

# Per-namespace resource consumption
oc adm top pods -A | grep -E "retail-edge|showroom"

# Storage utilization
oc get pvc -A | grep retail-edge

# Check for resource pressure
oc describe nodes | grep -A 5 "Allocated resources"
```

**Alerting thresholds:**
- ⚠️ **CPU > 80%**: Consider scaling down students or adding nodes
- ⚠️ **Memory > 80%**: VMs may experience performance degradation
- ❌ **Storage > 90%**: DataVolume provisioning may fail

### Prometheus Metrics (if available)

Query OpenShift Prometheus for workshop-specific metrics:

```promql
# VM restart count (high = stability issues)
sum(kubevirt_vm_restart_count{namespace=~"retail-edge-student-.*"}) by (namespace, name)

# Showroom pod restarts
sum(kube_pod_container_status_restarts_total{namespace=~"showroom-student-.*"}) by (namespace, pod)

# ArgoCD sync failures
argocd_app_sync_total{dest_namespace=~"retail-edge.*", phase="Failed"}
```

---

## Scaling

### Add Students (Scale Up)

Increase student count from 5 to 10:

```bash
# Update Helm values
cat > updated-values.yaml <<EOF
students:
  count: 10
# ... other values unchanged
EOF

# Upgrade Helm release
helm upgrade retail-edge-ha ./helm/retail-edge-ha \
  -n retail-edge-ha-gitops \
  -f updated-values.yaml

# Wait for new ArgoCD apps to sync
oc get applications -n retail-edge-ha-gitops -w
```

**Resources required (per student):**
- **Module 1 only**: 4 CPU, 8 GiB RAM, 60 GiB storage
- **Modules 1+2**: 8 CPU, 16 GiB RAM, 120 GiB storage
- **All modules**: 18 CPU, 36 GiB RAM, 200 GiB storage

**Deployment time:** 5-10 minutes for new student namespaces + Showroom instances.

### Remove Students (Scale Down)

Decrease student count from 10 to 5:

```bash
# Delete student namespaces 06-10
for i in $(seq -f "%02g" 6 10); do
  oc delete namespace retail-edge-student-$i --ignore-not-found
  oc delete namespace showroom-student-$i --ignore-not-found
done

# Delete ArgoCD applications for students 06-10
for i in $(seq -f "%02g" 6 10); do
  oc delete application retail-edge-ha-showroom-$i -n retail-edge-ha-gitops --ignore-not-found
  oc delete application retail-edge-ha-module1-$i -n retail-edge-ha-gitops --ignore-not-found
  oc delete application retail-edge-ha-module2-$i -n retail-edge-ha-gitops --ignore-not-found
  oc delete application retail-edge-ha-module3-$i -n retail-edge-ha-gitops --ignore-not-found
done

# Update Helm values
students:
  count: 5

# Upgrade Helm release
helm upgrade retail-edge-ha ./helm/retail-edge-ha \
  -n retail-edge-ha-gitops \
  -f updated-values.yaml
```

**Note:** Scaling down does not automatically delete resources. Manual cleanup recommended to free cluster capacity.

### Resource Planning Calculator

**For N students:**
- **CPU**: `N × (4 + 4M2 + 9M3)` where M2=1 if module2 enabled, M3=1 if module3 enabled
- **Memory**: `N × (8 + 8M2 + 18M3)` GiB
- **Storage**: `N × (60 + 60M2 + 80M3)` GiB
- **Namespaces**: `N × 2` (workload + UDN per student)
- **Showroom**: `N × 4` pods, `N × 1` GiB RAM

**Example for 50 students (all modules):**
- CPU: 50 × 18 = **900 cores**
- Memory: 50 × 36 = **1.8 TiB**
- Storage: 50 × 200 = **10 TiB**
- Pods: 50 × (9 VMs + 4 Showroom) = **650 pods**

**Recommended cluster size:** 12-15 worker nodes with 64 cores, 128 GiB RAM each.

---

## Maintenance

### Update Workshop Content

Update lab guides without redeploying VMs:

```bash
# Update workshop repository to latest
cd retail-edge-ha-workshop
git pull origin main

# Sync ArgoCD applications to pull latest content
for app in $(oc get applications -n retail-edge-ha-gitops -o name); do
  oc patch $app -n retail-edge-ha-gitops \
    --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
done

# Showroom will rebuild automatically with new content
oc get builds -A | grep showroom
```

**Impact:** Students will see updated content after ~2-3 minutes (Showroom rebuild time).

### Update VM Images (RHEL/RHCOS)

Change base VM image (e.g., RHEL 9.3 to RHEL 9.4):

```bash
# Update VM manifests
vim manifests/vms/module1-rhel-ha/vm-rhel-node1.yaml

# Change image URL
spec:
  template:
    spec:
      volumes:
      - containerDisk:
          image: quay.io/containerdisks/rhel:9.4  # Updated from 9.3
        name: containerdisk

# Commit and push changes
git add manifests/vms/
git commit -m "Update RHEL base image to 9.4"
git push origin main

# Sync ArgoCD (or wait for automatic sync)
oc patch application retail-edge-ha-module1-01 -n retail-edge-ha-gitops \
  --type merge -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

**Impact:** Existing running VMs not affected. Students must stop and restart VMs to use new image.

### Update Operator Versions

Upgrade OpenShift Virtualization operator:

```bash
# Check current version
oc get csv -n openshift-cnv

# Update subscription to latest channel
oc patch subscription kubevirt-hyperconverged -n openshift-cnv \
  --type merge -p '{"spec":{"channel":"stable"}}'

# Monitor upgrade
oc get csv -n openshift-cnv -w
```

**Impact:** VMs may experience brief pause (1-2 seconds) during live migration. Coordinate upgrades during workshop off-hours.

### Rotate Cluster Credentials

If cluster admin credentials change:

```bash
# Update Helm values with new cluster info
globalClusterApiUrl: "https://api.new-cluster.example.com:6443"
globalClusterDomain: "apps.new-cluster.example.com"

# Upgrade Helm release
helm upgrade retail-edge-ha ./helm/retail-edge-ha \
  -n retail-edge-ha-gitops \
  -f updated-values.yaml

# Update Showroom environment variables
./scripts/patch-showroom-terminals.sh $(grep "count:" values.yaml | awk '{print $2}')
```

---

## Backup and Restore

### Backup Workshop Configuration

Preserve current deployment state:

```bash
# Backup Helm values
helm get values retail-edge-ha -n retail-edge-ha-gitops > backup-values.yaml

# Backup ArgoCD application definitions
oc get applications -n retail-edge-ha-gitops -o yaml > backup-argocd-apps.yaml

# Backup student namespace configurations
for i in $(seq -f "%02g" 1 10); do
  oc get all,pvc,vm -n retail-edge-student-$i -o yaml > backup-student-$i.yaml
done

# Store backups securely
tar czf workshop-backup-$(date +%Y%m%d).tar.gz backup-*.yaml
```

### Restore Workshop

Restore from backup after accidental deletion:

```bash
# Extract backup
tar xzf workshop-backup-20250325.tar.gz

# Restore Helm release
helm install retail-edge-ha ./helm/retail-edge-ha \
  -n retail-edge-ha-gitops \
  --create-namespace \
  -f backup-values.yaml

# Wait for ArgoCD to reconcile
oc get applications -n retail-edge-ha-gitops -w
```

**Note:** VMs and PVCs will be recreated from manifests. Student data inside VMs is not preserved (VMs are ephemeral).

### Student Data Persistence

**Workshop design:** VMs are ephemeral (rebuilt from images). Student progress is NOT persisted between sessions.

**For persistent workshops:**
1. Use PVCs with `ReadWriteOnce` attached to VMs as secondary disks
2. Students save work to `/mnt/persistent` (mounted PVC)
3. Backup PVCs before cluster maintenance:

```bash
# Snapshot PVCs (if storage class supports snapshots)
oc get volumesnapshot -n retail-edge-student-01

# Or export PVC data
for pvc in $(oc get pvc -n retail-edge-student-01 -o name); do
  oc cp retail-edge-student-01/<pod>:/mnt/persistent ./backups/
done
```

---

## Security

### RBAC Validation

Verify students cannot access other students' namespaces:

```bash
# Impersonate student user
oc auth can-i get vms -n retail-edge-student-02 --as=student-01
# Expected: no

oc auth can-i get vms -n retail-edge-student-01 --as=student-01
# Expected: yes

# Check ClusterRoleBindings for excessive permissions
oc get clusterrolebindings | grep retail-edge
# Should only show workshop admin bindings, not student bindings
```

### Network Isolation Validation

Confirm students' VMs cannot communicate cross-namespace:

```bash
# From VM in student-01 namespace, try to ping VM in student-02
virtctl ssh cloud-user@rhel-ha-node1 -n retail-edge-student-01
$ ping 10.101.0.20  # Student-02's VM IP
# Expected: Timeout (UDNs are namespace-scoped)
```

### Image Scanning

Scan VM container disks for vulnerabilities:

```bash
# Scan RHEL base image
skopeo inspect docker://quay.io/containerdisks/rhel:9.3

# Use OpenShift's built-in image scanning (if enabled)
oc get imagemanifestvuln -A | grep rhel
```

**Recommendation:** Use Red Hat certified images from `registry.redhat.io` or `quay.io/containerdisks`.

### Secret Management

Workshop uses minimal secrets (SSH keys for VMs auto-generated by cloud-init):

```bash
# List secrets in student namespaces
oc get secrets -n retail-edge-student-01

# Rotate SSH keys (redeploy VMs)
oc delete vm rhel-ha-node1 -n retail-edge-student-01
# VM will be recreated by ArgoCD with new SSH key
```

---

## Incident Response

### Student Stuck - VM Won't Start

**Symptom:** Student reports VM stuck in "Pending" state

**Diagnosis:**
```bash
# Check DataVolume (disk provisioning)
oc get dv -n retail-edge-student-01
# Look for "Bound" status

# Check VM events
oc describe vm rhel-ha-node1 -n retail-edge-student-01 | grep -A 10 Events

# Check virt-launcher pod
oc get pods -n retail-edge-student-01 | grep virt-launcher
oc logs -n retail-edge-student-01 virt-launcher-rhel-ha-node1-xxxxx
```

**Resolution:**
```bash
# If DataVolume stuck, delete and let ArgoCD recreate
oc delete dv rhel-ha-node1 -n retail-edge-student-01

# If VM definition corrupt, force delete and recreate
oc delete vm rhel-ha-node1 -n retail-edge-student-01 --force --grace-period=0
```

### ArgoCD Out of Sync

**Symptom:** ArgoCD shows "OutOfSync" but manual `oc apply` works

**Diagnosis:**
```bash
# Check application diff
oc get application retail-edge-ha-module1-01 -n retail-edge-ha-gitops -o yaml | \
  yq '.status.sync.comparedTo.source'

# Compare cluster state vs Git
oc diff -f <(oc get -n retail-edge-ha-gitops application retail-edge-ha-module1-01 -o yaml)
```

**Resolution:**
```bash
# Force hard refresh
oc patch application retail-edge-ha-module1-01 -n retail-edge-ha-gitops \
  --type merge -p '{"operation":{"sync":{"syncStrategy":{"hook":{},"syncOptions":["CreateNamespace=true","PruneLast=true"]}}}}'

# Or delete and recreate application
oc delete application retail-edge-ha-module1-01 -n retail-edge-ha-gitops
helm template retail-edge-ha ./helm/retail-edge-ha | oc apply -f -
```

### Showroom Not Loading

**Symptom:** Student reports blank page or 404

**Diagnosis:**
```bash
# Check Showroom pods
oc get pods -n showroom-student-01

# Check Showroom route
oc get route -n showroom-student-01

# Check Showroom logs
oc logs -n showroom-student-01 deployment/showroom
oc logs -n showroom-student-01 deployment/showroom-content
```

**Resolution:**
```bash
# Rebuild Showroom content
oc delete pod -n showroom-student-01 -l app=showroom-content

# Check for GitHub rate limit (common issue)
oc logs -n showroom-student-01 deployment/showroom-content | grep "rate limit"
# If rate limited, wait 1 hour or use GitHub token

# Restart Showroom pods
oc rollout restart deployment/showroom -n showroom-student-01
```

### Cluster Resource Exhaustion

**Symptom:** VMs stuck in "Pending", pods in "CrashLoopBackOff"

**Diagnosis:**
```bash
# Check node resource availability
oc describe nodes | grep -A 5 "Allocated resources"

# Check for resource quotas
oc get resourcequota -A

# Check for limit ranges
oc get limitrange -A
```

**Resolution:**
- **Short-term:** Scale down students or disable Module 3 (most resource-intensive)
- **Long-term:** Add worker nodes or increase node capacity

---

## Performance Tuning

### Optimize VM Startup Time

```bash
# Use local storage for faster provisioning (if available)
virtualMachines:
  storageClass: "local-storage"  # Faster than network storage

# Pre-pull VM images to all nodes
oc adm image mirror quay.io/containerdisks/rhel:9.3 \
  --to=internal-registry.example.com/retail-edge
```

### Reduce Showroom Build Time

```bash
# Use pre-built Showroom image (avoid GitHub cloning)
showroom:
  content:
    repoUrl: "https://pre-built-content-server.example.com/workshop.tar.gz"
    usePreBuilt: true
```

### Parallel VM Provisioning

Enable parallel provisioning for faster deployments:

```yaml
# In Helm values
argocd:
  syncOptions:
    - CreateNamespace=true
    - PruneLast=true
  retry:
    limit: 5
    backoff:
      duration: 5s
      factor: 2
      maxDuration: 3m
```

---

## Cleanup and Decommissioning

### Full Workshop Deletion

```bash
# Uninstall Helm release (deletes ArgoCD apps)
helm uninstall retail-edge-ha -n retail-edge-ha-gitops

# Delete all student namespaces
oc delete namespace -l app.kubernetes.io/part-of=retail-edge-ha

# Force cleanup if namespaces stuck in Terminating
for ns in $(oc get ns | grep retail-edge | awk '{print $1}'); do
  oc get namespace $ns -o json | jq '.spec.finalizers = []' | oc replace --raw "/api/v1/namespaces/$ns/finalize" -f -
done

# Delete GitOps namespace
oc delete namespace retail-edge-ha-gitops
```

**Expected time:** 2-5 minutes for full cleanup.

---

## Support Contacts

- **GitHub Issues**: https://github.com/tosin2013/retail-edge-ha-workshop/issues
- **Documentation**: https://tosin2013.github.io/retail-edge-ha-workshop/
- **RHPDS Catalog**: Contact RHPDS team for catalog updates

---

**Last Updated:** 2025-03-25 | **Maintainer:** Workshop Operations Team
