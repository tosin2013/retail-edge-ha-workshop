# Getting Started with Retail Edge HA Workshop

**Time to deploy:** 5-10 minutes | **Target audience:** OpenShift cluster administrators

## What is This Workshop?

The Retail Edge HA Workshop teaches three high-availability architectures for retail edge computing environments:

1. **Module 1: Pacemaker HA** - Traditional RHEL clustering with STONITH fencing
2. **Module 2: MicroShift VRRP** - Lightweight Kubernetes with virtual IP failover
3. **Module 3: Two-Node OpenShift** - Compact OpenShift cluster with remote etcd arbiter
4. **Module 4: Chaos Engineering** - Resilience testing with fault injection

Each module includes hands-on labs with virtual machines running on OpenShift Virtualization.

---

## Prerequisites Checklist

Before deploying, ensure you have:

### Cluster Requirements
- [ ] **OpenShift 4.21 or higher** (tested on 4.21-4.23)
- [ ] **OpenShift Virtualization operator** installed and ready (check: `oc get csv -n openshift-cnv`)
- [ ] **OpenShift GitOps operator** (ArgoCD) - will be deployed automatically if missing
- [ ] **OVN-Kubernetes CNI** (required for User Defined Networks)
- [ ] **Storage class** available (preferably Ceph RBD for best performance)

### Cluster Resources (per student)
- **Module 1 only**: 4 CPU, 8 GiB RAM, 60 GiB storage
- **Modules 1+2**: 8 CPU, 16 GiB RAM, 120 GiB storage
- **All modules**: 18 CPU, 36 GiB RAM, 200 GiB storage

For 10 students with all modules: **180 CPU, 360 GiB RAM, 2 TiB storage**

### Local Tools
- [ ] **OpenShift CLI (`oc`)** - logged into cluster with cluster-admin
- [ ] **virtctl** CLI - for VM management (`brew install kubevirt/kubevirt/virtctl` or see [kubevirt.io](https://kubevirt.io/user-guide/operations/virtctl_client_tool/))
- [ ] **Helm 3.x** (optional, only for direct Helm deployment)
- [ ] **Git** (optional, for cloning repository)

### Credentials
- [ ] Cluster admin credentials (for deploying workshop infrastructure)
- [ ] Cluster API URL (e.g., `https://api.cluster-name.example.com:6443`)
- [ ] Cluster apps domain (e.g., `apps.cluster-name.example.com`)

---

## Quick Deployment (5 Steps)

### Step 1: Verify Cluster Prerequisites

```bash
# Check OpenShift version (must be 4.21+)
oc version

# Verify OpenShift Virtualization operator is installed
oc get csv -n openshift-cnv | grep kubevirt
# Expected output: kubevirt-hyperconverged-operator.v4.x.x   Succeeded

# Check available storage class
oc get storageclass
# Expected: At least one storage class (Ceph RBD preferred)

# Verify OVN-Kubernetes CNI
oc get network.config.openshift.io cluster -o jsonpath='{.spec.networkType}'
# Expected output: OVNKubernetes
```

If OpenShift Virtualization is **not** installed, see [OpenShift Virtualization Installation Guide](https://docs.openshift.com/container-platform/latest/virt/install/installing-virt.html).

### Step 2: Configure Workshop

Create a Helm values file with your cluster settings:

```bash
cat > my-workshop-values.yaml <<EOF
# Student configuration
students:
  count: 5  # Number of students (1-50)

# Cluster configuration (auto-discovered if left blank)
globalClusterDomain: "apps.cluster-cfz7p.dynamic.redhatworkshops.io"  # Your cluster apps domain
globalClusterApiUrl: "https://api.cluster-cfz7p.dynamic.redhatworkshops.io:6443"  # Your API URL

# Storage configuration
virtualMachines:
  storageClass: "ocs-external-storagecluster-ceph-rbd"  # Your storage class name
  autoStart: false  # Students manually start VMs (faster module startup)

# Module selection
modules:
  module1_pacemaker: true   # RHEL HA with Pacemaker
  module2_microshift: true  # MicroShift with VRRP
  module3_twonode: false    # Two-Node OpenShift (resource intensive - disabled by default)

# Showroom (web-based lab guide)
showroom:
  enabled: true  # Deploy containerized lab guide for each student
EOF
```

**Important:** Replace cluster domain and API URL with your actual cluster values.

### Step 3: Deploy with ArgoCD (Recommended)

```bash
# Clone workshop repository
git clone https://github.com/tosin2013/retail-edge-ha-workshop.git
cd retail-edge-ha-workshop

# Deploy using Helm App of Apps pattern
helm install retail-edge-ha ./helm/retail-edge-ha \
  --create-namespace \
  --namespace retail-edge-ha-gitops \
  --values my-workshop-values.yaml \
  --timeout 10m

# Watch ArgoCD sync progress
oc get applications -n retail-edge-ha-gitops -w
```

Press `Ctrl+C` when all applications show `Synced` and `Healthy`.

**Deployment time:** 5-10 minutes for infrastructure + Showroom, 3-5 minutes for VM creation per student.

### Step 4: Monitor Deployment

```bash
# Check student namespaces created
oc get namespaces | grep retail-edge-student
# Expected: retail-edge-student-01, 02, 03, ... (up to student count)

# Check Showroom pods running
oc get pods -n showroom-student-01
# Expected: showroom-xxxxx pod in Running state

# Check VMs created (stopped state - not running yet)
oc get vm -n retail-edge-student-01
# Expected: rhel-ha-node1, rhel-ha-node2 (Running: false)
```

### Step 5: Access Showroom Lab Guides

Get Showroom URLs for students:

```bash
# List all Showroom routes
for i in $(seq -f "%02g" 1 5); do
  echo "Student $i: https://$(oc get route -n showroom-student-$i -o jsonpath='{.items[0].spec.host}')"
done
```

Example output:
```
Student 01: https://showroom-showroom-student-01.apps.cluster-cfz7p.dynamic.redhatworkshops.io
Student 02: https://showroom-showroom-student-02.apps.cluster-cfz7p.dynamic.redhatworkshops.io
...
```

Share these URLs with students. No authentication required (workshop uses isolated namespaces).

---

## Verification (3 Quick Checks)

### ✅ Check 1: Namespaces Exist

```bash
oc get namespaces | grep -E "retail-edge-student|showroom-student"
```

Expected: 2 namespaces per student (workload + Showroom).

### ✅ Check 2: VMs Created

```bash
oc get vm -A | grep retail-edge
```

Expected: 2-9 VMs per student (depending on enabled modules).

### ✅ Check 3: Showroom Accessible

```bash
curl -I https://$(oc get route -n showroom-student-01 -o jsonpath='{.items[0].spec.host}')
```

Expected: `HTTP/2 200` response.

---

## Student Access

### Showroom Lab Guide

Students access the workshop via web browser:
- URL format: `https://showroom-showroom-student-XX.apps.<cluster-domain>`
- No credentials required
- Provides:
  - Lab instructions with copy-paste commands
  - Integrated terminal (runs `oc` commands directly)
  - Environment variable substitution (`%STUDENT_NAMESPACE%` auto-populated)

### VM Access

Students start VMs from Showroom terminal or local machine:

```bash
# Start VMs (takes ~30 seconds)
virtctl start rhel-ha-node1 -n retail-edge-student-01
virtctl start rhel-ha-node2 -n retail-edge-student-01

# Wait for VMs to reach Running state
oc get vmi -n retail-edge-student-01 -w

# SSH into VMs
virtctl ssh cloud-user@rhel-ha-node1 -n retail-edge-student-01
```

**Note:** VMs are pre-provisioned in stopped state for instant module startup. Students manually start VMs when beginning each module.

---

## Troubleshooting Quick Reference

### Issue 1: ArgoCD App Stuck in "Progressing"

**Symptom:** `oc get application -n retail-edge-ha-gitops` shows apps not syncing

**Solution:**
```bash
# Check ArgoCD controller logs
oc logs -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-application-controller

# Force manual sync
oc patch application retail-edge-ha -n retail-edge-ha-gitops \
  --type merge -p '{"operation":{"sync":{"syncStrategy":{"hook":{},"syncOptions":["CreateNamespace=true"]}}}}'
```

### Issue 2: VMs Won't Start

**Symptom:** `virtctl start` fails or VM stays in "Pending" state

**Solution:**
```bash
# Check DataVolume status (disk provisioning)
oc get dv -n retail-edge-student-01

# Check VM events
oc describe vm rhel-ha-node1 -n retail-edge-student-01

# Check virt-launcher pod logs
oc logs -n retail-edge-student-01 -l kubevirt.io=virt-launcher
```

### Issue 3: Showroom Build Fails

**Symptom:** Showroom pod in `ImagePullBackOff` or `CrashLoopBackOff`

**Solution:**
```bash
# Check BuildConfig status
oc get build -n showroom-student-01

# View build logs
oc logs -f bc/showroom -n showroom-student-01

# Check for GitHub rate limiting (common issue)
oc describe build showroom-1 -n showroom-student-01 | grep -i "rate limit"
```

**Workaround:** Wait 1 hour for GitHub rate limit reset, then rebuild:
```bash
oc start-build showroom -n showroom-student-01
```

### Issue 4: Students Can't SSH to VMs

**Symptom:** `virtctl ssh` fails with connection refused

**Solution:**
```bash
# Check VMI (VirtualMachineInstance) status
oc get vmi -n retail-edge-student-01

# Verify VM has IP address assigned
oc describe vmi rhel-ha-node1 -n retail-edge-student-01 | grep "IP Address"

# Use console access as fallback
virtctl console rhel-ha-node1 -n retail-edge-student-01
# Login: cloud-user / password: (none, SSH key-based)
```

### Issue 5: OpenShift Virtualization Operator Not Installed

**Symptom:** Deployment fails in pre-checks with "CNV operator not found"

**Solution:**
Install OpenShift Virtualization from OperatorHub:
```bash
cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-cnv
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: kubevirt-hyperconverged-group
  namespace: openshift-cnv
spec:
  targetNamespaces:
    - openshift-cnv
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: hco-operatorhub
  namespace: openshift-cnv
spec:
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  name: kubevirt-hyperconverged
  channel: "stable"
EOF

# Wait for operator to become ready (5-10 minutes)
oc wait --for=condition=Ready csv -n openshift-cnv -l operators.coreos.com/kubevirt-hyperconverged.openshift-cnv --timeout=600s
```

**Full documentation:** See [OpenShift Virtualization Docs](https://docs.openshift.com/container-platform/latest/virt/install/installing-virt.html)

---

## Next Steps

1. **Advanced Deployment Options**: See [DEPLOYMENT.md](./DEPLOYMENT.md) for:
   - Direct Helm deployment (without ArgoCD)
   - Manual Kustomize deployment
   - Scaling instructions (add/remove students)

2. **AgnosticD Integration**: See [agnosticd-integration/README.md](./agnosticd-integration/README.md) for:
   - RHPDS catalog deployment
   - AgnosticD v2 framework integration

3. **Operations Guide**: See [OPERATIONS.md](./OPERATIONS.md) for:
   - Monitoring and scaling
   - Maintenance procedures
   - Backup and restore

4. **Cluster Requirements**: See [cluster-requirements.md](./cluster-requirements.md) for:
   - Detailed version compatibility matrix
   - Storage backend compatibility
   - Resource planning calculator

5. **Contributing**: See [CONTRIBUTING.md](./CONTRIBUTING.md) for:
   - Adding new lab content
   - Testing procedures
   - Commit conventions

---

## Support

- **GitHub Issues**: https://github.com/tosin2013/retail-edge-ha-workshop/issues
- **Documentation**: https://tosin2013.github.io/retail-edge-ha-workshop/
- **Repository**: https://github.com/tosin2013/retail-edge-ha-workshop

---

## Quick Reference Card

| Task | Command |
|------|---------|
| Deploy workshop | `helm install retail-edge-ha ./helm/retail-edge-ha -n retail-edge-ha-gitops --create-namespace -f values.yaml` |
| List student namespaces | `oc get namespaces \| grep retail-edge-student` |
| Get Showroom URLs | `oc get routes -A \| grep showroom` |
| Start VM | `virtctl start <vm-name> -n <namespace>` |
| SSH to VM | `virtctl ssh cloud-user@<vm-name> -n <namespace>` |
| Check ArgoCD sync | `oc get applications -n retail-edge-ha-gitops` |
| Delete workshop | `helm uninstall retail-edge-ha -n retail-edge-ha-gitops` |
| Force namespace cleanup | `oc delete namespace retail-edge-ha-gitops retail-edge-student-{01..50} showroom-student-{01..50} --ignore-not-found` |

---

**Last Updated:** 2025-03-25 | **Tested on:** OpenShift 4.21.6 with CNV 4.16
