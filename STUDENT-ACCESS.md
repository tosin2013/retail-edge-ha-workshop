# Retail Edge HA Workshop - Student Access Guide

Welcome to the Retail Edge High-Availability Workshop! This guide will help you access your lab environment and begin working through the exercises.

## Your Workshop Environment

Each student has an isolated environment consisting of:

- **Lab Guide (Showroom)** - Interactive web-based instructions with embedded terminal
- **VirtualMachines** - RHEL-based VMs for hands-on exercises
- **Dedicated Namespace** - Your own OpenShift project with resource quotas
- **User Defined Networks** - Private networks for HA cluster communication

---

## Accessing Your Lab Guide

### Step 1: Get Your Lab Guide URL

Your instructor will provide you with your unique Showroom URL:

```
https://showroom-proxy-showroom-student-XX.apps.<cluster-domain>
```

Replace `XX` with your student number (01, 02, 03, etc.)

**Example:**
```
https://showroom-proxy-showroom-student-01.apps.cluster-cfz7p.dynamic.redhatworkshops.io
```

### Step 2: Open Lab Guide

1. Open the URL in your web browser (Chrome, Firefox, or Edge recommended)
2. The lab guide will load with:
   - **Content Pane** (left): Workshop instructions and exercises
   - **Terminal Pane** (right): Embedded terminal for running commands
   - **Module Navigation** (top): Jump between workshop modules

### Step 3: Verify Terminal Access

Click inside the terminal pane and run:

```bash
oc whoami
oc get projects | grep retail-edge-student
```

You should see your student namespace listed.

---

## Your Workshop Resources

### Namespaces

You have access to two namespaces:

1. **Workload Namespace**: `retail-edge-student-XX`
   - VirtualMachines
   - Storage (DataVolumes, PVCs)
   - ConfigMaps, Secrets

2. **UDN Namespace**: `retail-edge-student-XX-udn`
   - User Defined Networks (Layer 2 networks for HA clusters)
   - Network attachment definitions

### VirtualMachines

Depending on which modules are enabled, you may have:

**Module 1: RHEL HA with Pacemaker** (2 VMs)
- `rhel-ha-node1` - Pacemaker cluster node 1
- `rhel-ha-node2` - Pacemaker cluster node 2

**Module 2: MicroShift with VRRP** (2 VMs)
- `microshift-gw-a` - MicroShift gateway A
- `microshift-gw-b` - MicroShift gateway B

**Module 3: Two-Node OpenShift** (3 VMs)
- `twonode-master1` - Control plane node 1
- `twonode-master2` - Control plane node 2
- `twonode-arbiter` - Arbiter node

### Checking Your VMs

From the Showroom terminal:

```bash
# List all your VMs
oc get vms -n retail-edge-student-XX

# Check VM status (should show "Running")
oc get vms -n retail-edge-student-XX rhel-ha-node1

# Access VM console (web-based)
# Use OpenShift Console -> Virtualization -> VirtualMachines
```

**Default VM Credentials:**
- Username: `cloud-user`
- Password: `redhat`

---

## Workshop Modules

### Module 1: RHEL HA with Pacemaker/Corosync

**Objective:** Build a 2-node high-availability cluster using Pacemaker and Corosync

**What You'll Learn:**
- Configure Corosync for cluster heartbeat
- Set up Pacemaker for resource management
- Implement fencing with fence-agents-kubevirt
- Create virtual IP resources
- Test failover scenarios

**Duration:** ~90 minutes

### Module 2: MicroShift with VRRP (Optional)

**Objective:** Deploy highly-available edge Kubernetes using MicroShift and Keepalived

**What You'll Learn:**
- Install and configure MicroShift
- Set up Keepalived for VRRP-based failover
- Deploy applications on edge Kubernetes
- Test gateway failover

**Duration:** ~60 minutes

### Module 3: Two-Node OpenShift Cluster (Optional)

**Objective:** Deploy a compact OpenShift cluster for edge locations

**What You'll Learn:**
- Understand two-node OpenShift architecture
- Deploy control plane nodes with arbiter
- Configure cluster networking
- Manage edge clusters with RHACM

**Duration:** ~120 minutes

---

## Getting Help

### In the Lab Guide

- Each exercise includes step-by-step instructions
- Code blocks are copy-paste ready (click to copy)
- Expected outputs are shown for verification
- Troubleshooting tips are provided inline

### Common Issues

**Issue: Terminal won't connect**
- Refresh the browser page
- Clear browser cache and reload
- Ensure you're using a supported browser

**Issue: VM is not running**
- Check VM status: `oc get vms -n retail-edge-student-XX`
- If Stopped, contact instructor to restart it

**Issue: Can't find my namespace**
- Verify student number: `oc get projects | grep student`
- Check with instructor if namespace was created

**Issue: Commands fail with permission errors**
- Verify you're in the correct namespace: `oc project retail-edge-student-XX`
- Some commands require cluster-admin (instructor only)

### Asking for Help

If you encounter issues:

1. **Check the troubleshooting section** in the lab guide module
2. **Ask your instructor** - they can see your environment status
3. **Review error messages** - copy the full error to share with instructor
4. **Check VM console** - for VM-related issues, use the console in OpenShift web UI

---

## Workshop Best Practices

### Time Management
- Follow the suggested module order
- Don't skip verification steps
- Save complex troubleshooting for after completing basics
- Each module builds on previous concepts

### Using the Terminal
- Use the embedded terminal in Showroom (right pane)
- Commands are pre-configured for your environment
- Variables like `$STUDENT_ID` are automatically set
- Terminal session persists throughout the workshop

### VM Access
- **Web Console** (recommended): OpenShift Console → Virtualization → VirtualMachines → Console
- **SSH**: Not directly exposed; use web console
- **VNC**: Available through OpenShift console

### Resource Quotas
Your namespace has limits:
- **CPU**: 16 cores total
- **Memory**: 32 GiB total
- **Storage**: 200 GiB total
- **Pods**: 20 maximum
- **PVCs**: 10 maximum

Stay within these limits to avoid resource creation failures.

---

## Pre-Workshop Checklist

Before starting the exercises, verify:

- [ ] Lab guide URL opens successfully
- [ ] Terminal connects and shows prompt
- [ ] `oc whoami` returns your identity
- [ ] `oc get vms -n retail-edge-student-XX` shows your VMs
- [ ] VMs are in "Running" state (or "WaitingForVolumeBinding" if just started)
- [ ] Instructor has confirmed environment is ready

---

## Workshop Schedule (Typical)

**Morning Session (3 hours)**
- Introduction and environment orientation (30 min)
- Module 1: RHEL HA with Pacemaker (90 min)
- Break (15 min)
- Module 1 continued: Failover testing (45 min)

**Lunch Break** (60 min)

**Afternoon Session (3-4 hours)**
- Module 2: MicroShift with VRRP (60 min) _OR_
- Module 3: Two-Node OpenShift (120 min)
- Q&A and wrap-up (30 min)

_Schedule may vary depending on workshop format and student pace._

---

## Post-Workshop

### Lab Environment Access
- Your environment remains available for **X days** after the workshop
- After expiration, all resources will be deleted
- Export any work you want to keep before expiration

### Continuing Your Learning

**Red Hat Training:**
- [Red Hat High Availability Clustering (RH436)](https://www.redhat.com/en/services/training/rh436-red-hat-high-availability-clustering)
- [OpenShift Administration II (DO280)](https://www.redhat.com/en/services/training/do280-red-hat-openshift-administration-ii-operating-a-production-kubernetes-cluster)

**Documentation:**
- [Pacemaker Documentation](https://clusterlabs.org/pacemaker/doc/)
- [OpenShift Virtualization Documentation](https://docs.openshift.com/container-platform/latest/virt/about_virt/about-virt.html)
- [MicroShift Documentation](https://microshift.io/)

**Community:**
- [Red Hat Communities of Practice](https://www.redhat.com/en/blog/channel/red-hat-communities-practice)
- [OpenShift Commons](https://commons.openshift.org/)

---

## Feedback

We value your feedback! After the workshop:

- Complete the workshop survey (link provided by instructor)
- Share suggestions for improvement
- Report any technical issues encountered

---

**Questions During Workshop?**
👋 Raise your hand or ask in the chat - your instructor is here to help!

**Good luck and enjoy the workshop! 🚀**
