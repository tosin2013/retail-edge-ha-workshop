# User Testing Checklist - Showroom Multi-Instance

## Quick Status Summary

✅ **Ready for Testing:**
- Multi-instance Showroom deployed (5 students)
- Unique URLs per student
- Student-specific environment variables
- Workshop content accessible
- VMs deployed (stopped, ready to start)

⚠️ **Known Limitations:**
- Terminal doesn't include `oc`/`kubectl`/`virtctl` CLI tools (wetty image limitation)
- Students will use OpenShift web console or install tools manually

---

## Student URLs

**Test these URLs in a web browser:**

```
Student 01: https://showroom-proxy-showroom-student-01.apps.cluster-cfz7p.dynamic.redhatworkshops.io
Student 02: https://showroom-proxy-showroom-student-02.apps.cluster-cfz7p.dynamic.redhatworkshops.io
Student 03: https://showroom-proxy-showroom-student-03.apps.cluster-cfz7p.dynamic.redhatworkshops.io
Student 04: https://showroom-proxy-showroom-student-04.apps.cluster-cfz7p.dynamic.redhatworkshops.io
Student 05: https://showroom-proxy-showroom-student-05.apps.cluster-cfz7p.dynamic.redhatworkshops.io
```

---

## Test Checklist

### 1. Workshop Content Display ✅

**What to test:**
- [ ] Open Student 01 URL in browser
- [ ] Verify left panel shows "Retail Edge High Availability Workshop"
- [ ] Verify navigation shows 4 modules:
  - Module 1: Pacemaker HA
  - Module 2: MicroShift VRRP
  - Module 3: Two-Node OpenShift
  - Module 4: Chaos Engineering
- [ ] Click through each module, verify content loads
- [ ] Verify right panel shows "Terminal" tab

**Expected Result:** Workshop content displays correctly with all navigation working

**Known Issue:** One image missing (workshop-architecture.png) - shows 404 but doesn't affect functionality

---

### 2. Terminal Access ✅

**What to test:**
- [ ] Click "Terminal" tab in right panel
- [ ] Verify terminal interface loads (may take 5-10 seconds first time)
- [ ] Type a command: `echo "Hello from student terminal"`
- [ ] Verify command executes

**Expected Result:** Web-based terminal is functional

---

### 3. Environment Variables (Per Student) ✅

**What to test in terminal:**

```bash
# Check student-specific variables
echo $STUDENT_ID
echo $STUDENT_NAMESPACE
echo $STUDENT_USER
```

**Expected Results:**
- Student 01 terminal: `STUDENT_ID=01`, `STUDENT_NAMESPACE=retail-edge-student-01`, `STUDENT_USER=student-01`
- Student 02 terminal: `STUDENT_ID=02`, `STUDENT_NAMESPACE=retail-edge-student-02`, `STUDENT_USER=student-02`

**Verify isolation:**
- [ ] Open Student 01 URL → Terminal shows `STUDENT_ID=01`
- [ ] Open Student 02 URL → Terminal shows `STUDENT_ID=02`
- [ ] Confirm each student has different namespace/ID

---

### 4. VM Access Check

**Current Status:** VMs are deployed but **stopped** (intentional - autoStart: false)

**What to test via OpenShift Console:**

1. **Access student namespace:**
   - Go to OpenShift web console
   - Switch to "Administrator" perspective
   - Navigate to: Virtualization → VirtualMachines
   - Filter by namespace: `retail-edge-student-01`

2. **Verify VMs exist:**
   - [ ] rhel-ha-node1 (Module 1)
   - [ ] rhel-ha-node2 (Module 1)
   - [ ] microshift-gw-a (Module 2)
   - [ ] microshift-gw-b (Module 2)
   - [ ] twonode-master1 (Module 3)
   - [ ] twonode-master2 (Module 3)
   - [ ] twonode-arbiter (Module 3)

3. **Test starting a VM:**
   - [ ] Click on `rhel-ha-node1`
   - [ ] Click "Start" button
   - [ ] Wait for VM to reach "Running" state (~30-60 seconds)
   - [ ] Click "Console" tab to see VM console

**Expected Result:** VMs can be started and console is accessible

---

### 5. Multi-User Isolation Test ✅

**What to test:**

**Scenario:** Verify students don't interfere with each other

1. **In Student 01 terminal:**
   ```bash
   echo $STUDENT_NAMESPACE
   # Should output: retail-edge-student-01
   ```

2. **In Student 02 terminal (different browser/tab):**
   ```bash
   echo $STUDENT_NAMESPACE
   # Should output: retail-edge-student-02
   ```

3. **Via OpenShift Console:**
   - Start `rhel-ha-node1` in `retail-edge-student-01` namespace
   - Verify `rhel-ha-node1` in `retail-edge-student-02` namespace remains stopped
   - Confirms namespace isolation

**Expected Result:** Each student operates in isolated environment

---

## Known Limitations

### Terminal CLI Tools ⚠️

**Issue:** Terminal uses `wetty` image which doesn't include OpenShift CLI tools

**Workaround Options:**

1. **Use OpenShift Web Console** (Recommended)
   - All VM operations available via Virtualization → VirtualMachines
   - Start/Stop VMs
   - Access VM console
   - View VM details

2. **Install tools in terminal session** (Advanced)
   ```bash
   # In terminal, download oc CLI (not persistent across terminal restarts)
   wget https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-client-linux.tar.gz
   tar xvf openshift-client-linux.tar.gz
   ./oc version
   ```

3. **Use local CLI** (For instructors)
   - Install `oc` and `virtctl` on local machine
   - Login to cluster
   - Manage VMs from local terminal

**Impact:** Students will primarily use web console instead of CLI commands for VM management

---

## Success Criteria

**Workshop is ready for user testing if:**

- ✅ All 5 student URLs are accessible (HTTP 200)
- ✅ Workshop content loads in left panel
- ✅ Terminal opens in right panel
- ✅ Environment variables are student-specific
- ✅ VMs are visible in student namespaces
- ✅ VMs can be started via web console
- ⚠️ CLI tools limitation documented

**Current Status:** ✅ **READY FOR TESTING** (with CLI limitation noted)

---

## Troubleshooting

### Terminal not loading

```bash
# Check terminal pod status
oc get pods -n showroom-student-01 | grep terminal

# View terminal logs
oc logs -n showroom-student-01 deployment/showroom-terminal
```

### Environment variables not showing

```bash
# Verify ConfigMap exists
oc get configmap student-env -n showroom-student-01

# Re-run patch script
./scripts/patch-showroom-terminals.sh 5
```

### VMs not visible

```bash
# Check VMs in student namespace
oc get vms -n retail-edge-student-01

# VMs should show: 7 total (2 for Module 1, 2 for Module 2, 3 for Module 3)
```

### Content not loading

```bash
# Check content pod
oc get pods -n showroom-student-01 | grep content

# Check content logs
oc logs -n showroom-student-01 deployment/showroom-content
```

---

## Next Steps After Testing

1. **Gather Feedback:**
   - Workshop content clarity
   - Terminal usability
   - VM start/console workflow
   - Overall student experience

2. **Address CLI Tools:**
   - Consider building custom terminal image with oc/virtctl
   - OR update workshop instructions to use web console
   - OR provide pre-installed VM with tools

3. **Workshop Content:**
   - Test Module 1 lab instructions
   - Verify commands work with environment variables
   - Update any CLI-dependent steps to web console steps

4. **Scale Testing:**
   - Currently deployed: 5 students
   - Can scale to 50 students (requires more cluster resources)
   - Test with 10-15 concurrent students to verify performance
