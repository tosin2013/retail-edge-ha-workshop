# Retail Edge HA Workshop - Deployment Guide

Complete GitOps deployment guide for the Retail Edge High-Availability Workshop.

## Quick Start

### Prerequisites

- OpenShift 4.21+ with:
  - OpenShift Virtualization operator installed
  - OpenShift GitOps (ArgoCD) operator installed
  - Storage class configured (e.g., `ocs-external-storagecluster-ceph-rbd`)
  - Red Hat Advanced Cluster Management 2.16+ (optional, for fleet management)
- Cluster admin access
- `oc` CLI installed
- Git repository forked (if making custom modifications)

### Pre-Deployment Checklist

Before deploying the workshop, verify these critical settings:

**✅ values.yaml Configuration**
- [ ] `global.clusterDomain` matches your cluster's ingress domain
- [ ] `global.clusterApiUrl` matches your cluster's API server URL
- [ ] `students.count` is set to desired number of students (1-50)
- [ ] `virtualMachines.autoStart` is `true` (VMs should start automatically)
- [ ] `showroom.chart.version` is set to a valid version (e.g., "0.4.9")
- [ ] `showroom.enabled` is `true` (lab guides required for students)
- [ ] Storage class name matches your cluster's available storage

**✅ Operators Ready**
```bash
# Verify operators are installed and ready
oc get csv -n openshift-cnv | grep kubevirt-hyperconverged
oc get csv -n openshift-gitops | grep openshift-gitops-operator
oc get csv -n open-cluster-management | grep advanced-cluster-management  # Optional
```

**✅ Storage Available**
```bash
# Verify default storage class exists
oc get storageclass | grep "(default)"
```

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
- **1 Build Namespace**: For Showroom image builds
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
- **BuildConfig**: Builds Showroom image from GitHub
- **5 Showroom Deployments**: One per student with personalized lab guide
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
   - Wave 3: Showroom

6. **Access workshop:**
   ```bash
   # Get student URLs
   oc get routes -A | grep showroom

   # Example output:
   # retail-edge-student-01  showroom  showroom-retail-edge-student-01.apps...
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

   # Generate Showroom
   ./scripts/generate-showroom-deployments.sh 5
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

   # Showroom
   oc apply -f showroom/deploy/build.yaml
   for i in {01..05}; do
     oc apply -f manifests/showroom/showroom-student-${i}.yaml
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

### Build Showroom Image

Trigger the initial build:

```bash
oc start-build retail-edge-ha-showroom -n retail-edge-workshop
oc logs -f bc/retail-edge-ha-showroom -n retail-edge-workshop
```

Wait 3-5 minutes for build to complete.

### Verify Deployments

```bash
# Check all Showroom pods
oc get pods -A | grep showroom

# Check student namespaces
oc get namespaces | grep retail-edge-student

# Check VMs
oc get vm -n retail-edge-student-01
```

### Access Workshop

Students navigate to:

```
https://showroom-retail-edge-student-01.<cluster-domain>/workshop/
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

### Showroom Build Failing

**Symptom:** BuildConfig errors

**Solution:**
```bash
# Check build logs
oc logs -f bc/retail-edge-ha-showroom -n retail-edge-workshop

# Common issue: GitHub rate limit
# Wait 5 minutes and retry:
oc start-build retail-edge-ha-showroom -n retail-edge-workshop
```

### Students Can't Access Workshop

**Symptom:** Route 404 or connection refused

**Solution:**
```bash
# Check Route exists
oc get route showroom -n retail-edge-student-01

# Check Showroom pod running
oc get pods -n retail-edge-student-01

# Check image pulled successfully
oc describe pod -n retail-edge-student-01 -l app=showroom
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
   vim showroom/workshop/content/module1-pacemaker.adoc
   ```

2. **Commit changes:**
   ```bash
   git add showroom/
   git commit -m "Update Module 1 lab guide"
   git push origin main
   ```

3. **Rebuild Showroom:**
   ```bash
   # ArgoCD auto-triggers build on ConfigChange
   # Or manually:
   oc start-build retail-edge-ha-showroom -n retail-edge-workshop
   ```

4. **Restart Showroom pods:**
   ```bash
   oc rollout restart deployment/showroom -n retail-edge-student-01
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
- Use persistent storage for Showroom (PVCs)
- Enable pod disruption budgets
- Configure horizontal pod autoscaling for Showroom

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

---

## Post-Deployment Verification

After deploying the workshop, run these checks to ensure everything is ready for students:

### 1. Verify ArgoCD Applications

```bash
# Check parent application
oc get application.argoproj.io retail-edge-ha -n openshift-gitops

# Expected: SYNC STATUS = Synced, HEALTH STATUS = Healthy

# Check child applications
oc get application.argoproj.io -n openshift-gitops | grep retail-edge

# Expected: All applications should show Synced/Healthy
```

### 2. Verify Showroom Lab Guides

```bash
# Check Showroom pods
oc get pods -A | grep showroom

# Expected: showroom, showroom-content, showroom-proxy, showroom-terminal pods Running

# Check Showroom routes
oc get routes -A | grep showroom

# Get student lab guide URLs
for i in 01 02; do
  echo "Student $i: https://$(oc get route showroom-proxy -n showroom-student-$i -o jsonpath='{.spec.host}')"
done
```

### 3. Verify VirtualMachines

```bash
# Check VM status for student 01
oc get vms -n retail-edge-student-01

# Expected: STATUS = Running or WaitingForVolumeBinding (if DataVolumes still importing)
# NOT Expected: Stopped (indicates autoStart issue)

# Check DataVolume import progress
oc get datavolume -n retail-edge-student-01

# Expected: PHASE = Succeeded (after 2-5 minutes)
# In Progress: ImportInProgress or PendingPopulation
```

### 4. Student Readiness Check

Run the automated student readiness check:

```bash
./scripts/validate-workshop-deployment.sh --students 2 --format both
```

**Expected Results:**
- ✅ Infrastructure checks: 8/8 passed
- ✅ Showroom accessible: HTTP 200
- ✅ VMs: Running state
- ✅ DataVolumes: Succeeded state

If validation fails, see **Troubleshooting** section below.

---

## Troubleshooting

### Issue: ArgoCD Application Shows "OutOfSync" or "Failed"

**Symptoms:**
- `oc get application.argoproj.io retail-edge-ha -n openshift-gitops` shows OutOfSync or Failed

**Common Causes:**
1. **Missing Showroom chart version** - Check `showroom.chart.version` in values.yaml
2. **Invalid cluster domain** - Verify `global.clusterDomain` matches `oc get ingresses.config/cluster -o jsonpath='{.spec.domain}'`
3. **Network connectivity** - ArgoCD can't reach GitHub repository

**Fix:**
```bash
# Check Application status
oc get application.argoproj.io retail-edge-ha -n openshift-gitops -o jsonpath='{.status.operationState.message}'

# Force refresh and sync
oc annotate application.argoproj.io retail-edge-ha -n openshift-gitops argocd.argoproj.io/refresh=normal --overwrite

# If still failing, check child applications
oc get application.argoproj.io -n openshift-gitops | grep retail-edge
oc describe application.argoproj.io retail-edge-ha-showroom-01 -n openshift-gitops
```

### Issue: Showroom Not Deployed

**Symptoms:**
- No Showroom pods running
- No routes created
- Students can't access lab guides

**Common Causes:**
1. `showroom.enabled: false` in values.yaml
2. Missing or invalid `showroom.chart.version`
3. Showroom ArgoCD Application sync failed

**Fix:**
```bash
# Verify Showroom is enabled
grep "showroom:" -A 5 helm/retail-edge-ha/values.yaml | grep enabled

# Check Showroom chart version
helm search repo showroom-deployer/showroom --versions | head -10

# Update values.yaml with correct version (e.g., 0.4.9)
# Then refresh ArgoCD Application
```

### Issue: All VMs are Stopped

**Symptoms:**
- `oc get vms -n retail-edge-student-01` shows STATUS = Stopped
- Students can't access VMs
- DataVolumes show PendingPopulation indefinitely

**Common Causes:**
1. `virtualMachines.autoStart: false` in values.yaml
2. VM manifests have `running: false`
3. VMs were created before autoStart was enabled

**Fix:**
```bash
# Check values.yaml setting
grep "autoStart:" helm/retail-edge-ha/values.yaml

# If false, update to true and push changes

# For existing stopped VMs, start manually:
for ns in retail-edge-student-01 retail-edge-student-02; do
  for vm in rhel-ha-node1 rhel-ha-node2; do
    oc patch vm $vm -n $ns --type merge -p '{"spec":{"running":true}}'
  done
done
```

### Issue: DataVolumes Stuck in PendingPopulation

**Symptoms:**
- DataVolumes never transition to ImportInProgress or Succeeded
- VMs stay in WaitingForVolumeBinding

**Common Causes:**
1. Storage class uses WaitForFirstConsumer binding mode (expected behavior)
2. VMs are stopped (not consuming volumes)
3. Storage provisioner issues

**Fix:**
```bash
# Verify VMs are running (required for WaitForFirstConsumer storage)
oc get vms -A | grep retail-edge

# If VMs are Running, wait 2-5 minutes for import
# Check import progress
watch oc get datavolume -A

# If still stuck after 10 minutes, check CDI pods
oc get pods -n openshift-cnv | grep cdi-

# Check import logs
oc logs -n openshift-cnv -l app=containerized-data-importer
```

### Issue: Student Routes Not Accessible

**Symptoms:**
- Routes exist but return 404 or connection refused
- Students can't access lab guides

**Common Causes:**
1. Pods not ready yet
2. Ingress controller issues
3. Network policy blocking access

**Fix:**
```bash
# Check pod status
oc get pods -n showroom-student-01

# Test route from within cluster
oc run curl-test --rm -it --image=curlimages/curl -- sh
# Inside pod: curl -I http://showroom-proxy.showroom-student-01.svc:8080

# Check route configuration
oc describe route showroom-proxy -n showroom-student-01
```

### Issue: Showroom Terminal Asks for Username

**Symptoms:**
- Terminal displays login prompt asking for username/password
- Students cannot access shell to run commands
- Terminal shows "Login:" prompt instead of shell

**Root Cause:**
WeTTY (`docker.io/wettyoss/wetty:latest`) is an SSH client that requires authentication credentials (SSHUSER, SSHHOST, SSHPASS). When these are not configured, it displays an interactive login prompt.

**Solution:**
Switch to ttyd-based terminal which provides direct shell access without authentication.

**Fix Steps:**
```bash
# 1. Update values.yaml (line 361)
# Change: image: docker.io/wettyoss/wetty:latest
# To:     image: docker.io/tsl0922/ttyd:latest

# 2. Commit and push
git add helm/retail-edge-ha/values.yaml
git commit -m "Fix terminal - switch from WeTTY to ttyd"
git push origin main

# 3. Trigger ArgoCD sync
oc annotate application.argoproj.io retail-edge-ha -n openshift-gitops \
  argocd.argoproj.io/refresh=normal --overwrite

# 4. Force sync Showroom applications
for app in retail-edge-ha-showroom-01 retail-edge-ha-showroom-02; do
  oc patch application.argoproj.io $app -n openshift-gitops --type merge \
    -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"syncStrategy":{"hook":{}}}}}'
done

# 5. Wait for terminal pods to rollout
oc get pods -n showroom-student-01 -w
```

**Verify Fix:**
```bash
# Check terminal image
oc get pods -n showroom-student-01 -l app=showroom-terminal \
  -o jsonpath='{.items[0].spec.containers[0].image}'

# Expected: docker.io/tsl0922/ttyd:latest

# Test in browser - should see immediate shell prompt (no login)
```

**Important Note - CLI Tools:**
The ttyd image does NOT include `oc` or `virtctl` pre-installed. Solutions:

**Option A:** Students install tools in terminal session:
```bash
curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz
tar xzf openshift-client-linux.tar.gz && chmod +x oc kubectl
export PATH=$PATH:$(pwd)
```

**Option B:** Add init container to Showroom deployment (requires Helm chart customization)

**Option C:** Document using OpenShift web console for VM management instead

---

## Common Deployment Mistakes to Avoid

1. **❌ Don't deploy without verifying values.yaml** - Always check cluster domain, API URL, and chart versions
2. **❌ Don't assume operators are ready** - Wait for CSVs to reach Succeeded phase before deploying
3. **❌ Don't skip Showroom** - Students need lab guides! Set `showroom.enabled: true`
4. **❌ Don't use `running: false` in production** - Set `virtualMachines.autoStart: true`
5. **❌ Don't forget to test one student environment first** - Validate before scaling to all students

---

## Success Criteria

Your workshop is ready for students when:

✅ ArgoCD Application is Synced and Healthy  
✅ All Showroom routes return HTTP 200  
✅ All VMs are in Running state  
✅ All DataVolumes are in Succeeded phase  
✅ Student readiness validation passes with 0 failures  

**Estimated deployment time:** 15-20 minutes (including DataVolume imports)

---

## Need Help?

- **Workshop Repository:** https://github.com/tosin2013/retail-edge-ha-workshop
- **Validation Report:** Run `./scripts/validate-workshop-deployment.sh --help`
- **ArgoCD UI:** `oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'`

