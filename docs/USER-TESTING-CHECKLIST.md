# User Testing Checklist — Retail Edge HA Workshop

## Quick Status Summary

Before testing, generate the access info file to get all URLs and credentials:

```bash
cd ~/Development/agnosticd-v2-vars/retail-edge-ha
HUB_GUID=retail-ha NUM_STUDENTS=2 ./print-access-info.sh
# Saves to: ~/Development/agnosticd-v2-output/retail-ha/access-info.txt
```

**Ready for Testing When:**
- All ArgoCD applications show `Synced` or `Healthy`
- Student Showroom URLs are accessible
- Student namespaces contain 4 VMs (2 for Module 1, 2 for Module 2)
- Showroom terminals open and display student-specific environment variables

---

## Get Student URLs (Dynamic)

```bash
KC=~/Development/agnosticd-v2-output/retail-ha/openshift-cluster_retail-ha_kubeconfig

oc --kubeconfig="$KC" get routes -A \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{": https://"}{.spec.host}{"\n"}{end}' \
  | grep showroom-student | sort
```

---

## Test Checklist

### 1. ArgoCD Applications Healthy

```bash
KC=~/Development/agnosticd-v2-output/retail-ha/openshift-cluster_retail-ha_kubeconfig
oc --kubeconfig="$KC" get applications -n openshift-gitops
```

**Expected applications:**

| Application | Expected Status |
|---|---|
| `retail-edge-ha` | Synced / Healthy |
| `retail-edge-ha-networking` | Synced / Healthy |
| `retail-edge-ha-operators` | Synced / Healthy |
| `retail-edge-ha-showroom-01` | Synced / Healthy |
| `retail-edge-ha-showroom-02` | Synced / Healthy |
| `retail-edge-ha-showroom-config` | Synced / Healthy |
| `retail-edge-ha-vms-module1` | Synced / Healthy |
| `retail-edge-ha-vms-module2` | Synced / Healthy |

**Note:** `retail-edge-ha-vms-module3` should NOT appear — Module 3 uses real AWS OCP clusters, not KubeVirt VMs.

---

### 2. Workshop Content Display

**What to test:**
- [ ] Open Student 01 Showroom URL in browser
- [ ] Verify left panel shows "Retail Edge High Availability Workshop"
- [ ] Verify navigation shows 3 modules:
  - Module 1: Pacemaker HA
  - Module 2: MicroShift VRRP
  - Module 3: Two-Node OpenShift (AWS)
- [ ] Click through each module, verify content loads
- [ ] Verify right panel shows "Terminal" tab

**Expected Result:** Workshop content displays correctly with all navigation working.

---

### 3. Terminal Access

**What to test:**
- [ ] Click "Terminal" tab in right panel
- [ ] Verify terminal interface loads (may take 5–10 seconds first time)
- [ ] Type a command: `echo "Hello from student terminal"`
- [ ] Verify command executes

**Expected Result:** Web-based terminal is functional.

---

### 4. Environment Variables (Per Student)

**What to test in terminal:**

```bash
# Check student-specific variables
echo $STUDENT_ID
echo $STUDENT_NAMESPACE
echo $STUDENT_USER

# Module 1 variables
echo $RHEL_NODE1
echo $PACEMAKER_IP1
echo $PACEMAKER_VIP

# Module 2 variables
echo $MICROSHIFT_GWA
echo $MICROSHIFT_GWA_IP
echo $MICROSHIFT_VIP

# Module 3 variables
echo $MODULE3_CLUSTER
```

**Expected Results:**

| Variable | Student 01 | Student 02 |
|---|---|---|
| `STUDENT_ID` | `01` | `02` |
| `STUDENT_NAMESPACE` | `retail-edge-student-01` | `retail-edge-student-02` |
| `RHEL_NODE1` | `rhel-ha-node1` | `rhel-ha-node1` |
| `PACEMAKER_VIP` | `10.101.0.100` | `10.101.0.100` |
| `MICROSHIFT_VIP` | `10.102.0.100` | `10.102.0.100` |
| `MODULE3_CLUSTER` | `student-01-twonode` | `student-02-twonode` |

**Verify isolation:**
- [ ] Open Student 01 URL → Terminal shows `STUDENT_ID=01`
- [ ] Open Student 02 URL → Terminal shows `STUDENT_ID=02`
- [ ] Confirm each student has a different namespace and Module 3 cluster name

---

### 5. VM Access Check (Modules 1 & 2)

Each student namespace contains **4 VMs** (2 per module — Module 3 uses AWS clusters, not VMs):

```bash
KC=~/Development/agnosticd-v2-output/retail-ha/openshift-cluster_retail-ha_kubeconfig

# Verify VMs exist
for ns in retail-edge-student-01 retail-edge-student-02; do
  echo "=== $ns ==="
  oc --kubeconfig="$KC" get vm -n "$ns" -o wide
done
```

**Expected VMs per student namespace:**

| VM Name | Module | Purpose |
|---|---|---|
| `rhel-ha-node1` | Module 1 | Pacemaker cluster node 1 |
| `rhel-ha-node2` | Module 1 | Pacemaker cluster node 2 |
| `microshift-gw-a` | Module 2 | MicroShift VRRP gateway A |
| `microshift-gw-b` | Module 2 | MicroShift VRRP gateway B |

**Test starting a VM:**
- [ ] `virtctl start rhel-ha-node1 -n retail-edge-student-01`
- [ ] Wait ~60 seconds for VM to reach Running state
- [ ] `virtctl ssh cloud-user@rhel-ha-node1 -n retail-edge-student-01` (password: `redhat`)

---

### 6. Module 3 — Two-Node OCP Cluster Check

Module 3 uses a dedicated AWS OCP cluster per student, managed through RHACM. The hub workload creates placeholder namespaces; actual clusters are provisioned separately.

**Check RHACM managed clusters:**

```bash
KC=~/Development/agnosticd-v2-output/retail-ha/openshift-cluster_retail-ha_kubeconfig

oc --kubeconfig="$KC" get managedclusters
```

If student clusters have been provisioned:

```bash
# Check a specific student cluster
oc --kubeconfig="$KC" get managedcluster student-01-twonode \
  -o jsonpath='{.status.conditions[?(@.type=="ManagedClusterConditionAvailable")].status}'
# Expected: True
```

If clusters are not yet provisioned, run:

```bash
cd ~/Development/agnosticd-v2-vars/retail-edge-ha
NUM_STUDENTS=2 ./cluster-deploy.sh
# (Phase 3 provisions the per-student two-node clusters)
```

---

### 7. Multi-User Isolation Test

**Scenario:** Verify students don't interfere with each other.

1. **Start a VM for Student 01:**
   ```bash
   virtctl start rhel-ha-node1 -n retail-edge-student-01
   ```

2. **Verify Student 02's VM is unaffected:**
   ```bash
   oc get vm rhel-ha-node1 -n retail-edge-student-02 \
     -o jsonpath='{.status.printableStatus}'
   # Expected: Stopped
   ```

3. **In Student 01 Showroom terminal:**
   ```bash
   echo $STUDENT_NAMESPACE
   # Expected: retail-edge-student-01
   ```

4. **In Student 02 Showroom terminal (different browser/tab):**
   ```bash
   echo $STUDENT_NAMESPACE
   # Expected: retail-edge-student-02
   ```

**Expected Result:** Each student operates in a fully isolated environment.

---

## Success Criteria

Workshop is ready for delivery when:

- [ ] All ArgoCD applications are `Synced/Healthy`
- [ ] All student Showroom URLs are accessible (HTTP 200)
- [ ] Workshop content loads in left panel (3 modules listed)
- [ ] Terminal opens in right panel
- [ ] Environment variables are student-specific and correct
- [ ] Each student namespace has exactly 4 VMs (Module 1 + Module 2)
- [ ] `retail-edge-ha-vms-module3` ArgoCD app does NOT exist
- [ ] RHACM shows managed clusters for Module 3 (if student clusters provisioned)

---

## Troubleshooting

### Showroom terminal not loading

```bash
KC=~/Development/agnosticd-v2-output/retail-ha/openshift-cluster_retail-ha_kubeconfig

oc --kubeconfig="$KC" get pods -n showroom-student-01 | grep terminal
oc --kubeconfig="$KC" logs -n showroom-student-01 deployment/showroom-terminal
```

### Environment variables not showing in terminal

Verify the Showroom config ArgoCD application is synced and the namespace has the ArgoCD management label:

```bash
KC=~/Development/agnosticd-v2-output/retail-ha/openshift-cluster_retail-ha_kubeconfig

oc --kubeconfig="$KC" get application retail-edge-ha-showroom-config -n openshift-gitops
oc --kubeconfig="$KC" get configmap student-env -n showroom-student-01
```

### VMs not visible in student namespace

```bash
KC=~/Development/agnosticd-v2-output/retail-ha/openshift-cluster_retail-ha_kubeconfig

# Expected: 4 VMs per namespace
oc --kubeconfig="$KC" get vms -n retail-edge-student-01

# Check module1 and module2 ArgoCD apps
oc --kubeconfig="$KC" get application retail-edge-ha-vms-module1 -n openshift-gitops -o jsonpath='{.status.health.status}'
oc --kubeconfig="$KC" get application retail-edge-ha-vms-module2 -n openshift-gitops -o jsonpath='{.status.health.status}'
```

### Module 3 cluster not joining RHACM

```bash
KC=~/Development/agnosticd-v2-output/retail-ha/openshift-cluster_retail-ha_kubeconfig

# Check import job status
oc --kubeconfig="$KC" get pods -n student-01-twonode | grep import

# Check auto-import secret is present
oc --kubeconfig="$KC" get secret auto-import-secret -n student-01-twonode
```

### Content not loading

```bash
KC=~/Development/agnosticd-v2-output/retail-ha/openshift-cluster_retail-ha_kubeconfig

oc --kubeconfig="$KC" get pods -n showroom-student-01 | grep content
oc --kubeconfig="$KC" logs -n showroom-student-01 deployment/showroom-content
```

---

## Next Steps After Testing

1. **Gather Feedback:**
   - Workshop content clarity and accuracy
   - Terminal usability for lab steps
   - Module 3 two-node cluster accessibility via RHACM
   - Overall student experience

2. **Scale Testing:**
   - Default deployment: 2 students
   - Increase `NUM_STUDENTS` for larger groups
   - Test with 10–15 concurrent students to verify performance

3. **Module 3 Cluster Provisioning:**
   - Student two-node clusters are provisioned separately via `cluster-deploy.sh` Phase 3
   - Provisioning takes ~45 minutes per cluster (parallelized)
   - Verify RHACM import completes before the workshop begins
