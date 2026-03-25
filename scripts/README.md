# Workshop Automation Scripts

This directory contains automation scripts for workshop deployment, scaling, and maintenance.

---

## Table of Contents

1. [generate-vm-manifests.sh](#generate-vm-manifestssh) - Generate VirtualMachine manifests for N students
2. [generate-udn-manifests.sh](#generate-udn-manifestssh) - Generate User Defined Network manifests for N students
3. [patch-showroom-terminals.sh](#patch-showroom-terminalssh) - Inject student environment variables into Showroom terminals
4. [validate-deployment.sh](#validate-deploymentsh) - Validate workshop deployment health

---

## generate-vm-manifests.sh

### Purpose

Generates VirtualMachine YAML manifests for a specified number of students across all enabled modules.

### Usage

```bash
./scripts/generate-vm-manifests.sh <student_count>
```

### Parameters

| Parameter | Description | Default | Valid Range |
|-----------|-------------|---------|-------------|
| `student_count` | Number of students | (required) | 1-50 |

### Example

```bash
# Generate VMs for 25 students
./scripts/generate-vm-manifests.sh 25
```

### Output

Creates manifests in:
- `manifests/vms/module1-rhel-ha/vm-rhel-node1.yaml` (2 VMs per student)
- `manifests/vms/module1-rhel-ha/vm-rhel-node2.yaml`
- `manifests/vms/module2-microshift/vm-microshift-gw-a.yaml` (2 VMs per student)
- `manifests/vms/module2-microshift/vm-microshift-gw-b.yaml`
- `manifests/vms/module3-twonode/vm-twonode-master1.yaml` (3 VMs per student)
- `manifests/vms/module3-twonode/vm-twonode-master2.yaml`
- `manifests/vms/module3-twonode/vm-twonode-arbiter.yaml`

### VM Specifications

#### Module 1 (RHEL HA - Pacemaker)
```yaml
VMs per student: 2
  - rhel-ha-node1: 2 cores, 4 GiB RAM, 30 GiB disk
  - rhel-ha-node2: 2 cores, 4 GiB RAM, 30 GiB disk
Image: quay.io/containerdisks/rhel:9.3
Network: pacemaker-net (10.101.0.0/24)
  - node1: 10.101.0.20
  - node2: 10.101.0.21
Cloud-init: Installs pacemaker, pcs, fence-agents-kubevirt, corosync
```

#### Module 2 (MicroShift)
```yaml
VMs per student: 2
  - microshift-gw-a: 2 cores, 4 GiB RAM, 30 GiB disk
  - microshift-gw-b: 2 cores, 4 GiB RAM, 30 GiB disk
Image: quay.io/microshift/microshift-installer:latest
Network: microshift-net (10.102.0.0/24)
  - gw-a: 10.102.0.20
  - gw-b: 10.102.0.21
  - VIP: 10.102.0.100
Cloud-init: Installs MicroShift, keepalived, haproxy
```

#### Module 3 (Two-Node OpenShift)
```yaml
VMs per student: 3
  - twonode-master1: 3 cores, 6 GiB RAM, 40 GiB disk
  - twonode-master2: 3 cores, 6 GiB RAM, 40 GiB disk
  - twonode-arbiter: 1 core, 2 GiB RAM, 10 GiB disk
Image: RHCOS 4.21 (openshift-release-dev)
Network: twonode-net (10.103.0.0/24)
  - master1: 10.103.0.20
  - master2: 10.103.0.21
  - arbiter: 10.103.0.22
Cloud-init: Bootstrap-in-Place ignition configs
```

### Customization

Edit VM templates before generating:

```bash
vim manifests/vms/module1-rhel-ha/vm-rhel-node1-template.yaml
# Modify CPU, memory, or disk size
# Then regenerate
./scripts/generate-vm-manifests.sh 25
```

### Verification

```bash
# Count generated VMs
ls manifests/vms/module1-rhel-ha/vm-*.yaml | wc -l
# Expected: 2 files (node1 + node2)

# Check VM namespaces
grep "namespace:" manifests/vms/module1-rhel-ha/vm-rhel-node1.yaml
# Should show: retail-edge-student-01, 02, ..., 25
```

### Troubleshooting

**Issue:** Script fails with "template not found"

**Solution:**
```bash
# Ensure you're in repository root
cd /path/to/retail-edge-ha-workshop
./scripts/generate-vm-manifests.sh 25
```

**Issue:** Generated VMs have wrong IP addresses

**Solution:**
```bash
# Verify IP allocation in script
grep "PACEMAKER_IP" scripts/generate-vm-manifests.sh
# Should increment per student: 10.101.0.20 (student01), 10.201.0.20 (student02), etc.
```

---

## generate-udn-manifests.sh

### Purpose

Generates User Defined Network (UDN) YAML manifests for Layer 2 VM connectivity across all modules.

### Usage

```bash
./scripts/generate-udn-manifests.sh <student_count>
```

### Parameters

| Parameter | Description | Default | Valid Range |
|-----------|-------------|---------|-------------|
| `student_count` | Number of students | (required) | 1-50 |

### Example

```bash
# Generate UDNs for 10 students
./scripts/generate-udn-manifests.sh 10
```

### Output

Creates manifests in:
- `manifests/networking/udn-module1/udn-pacemaker.yaml` (10.101.0.0/24 per student)
- `manifests/networking/udn-module2/udn-microshift.yaml` (10.102.0.0/24 per student)
- `manifests/networking/udn-module3/udn-twonode.yaml` (10.103.0.0/24 per student)

### UDN Specifications

```yaml
Module 1 (Pacemaker):
  Name: pacemaker-net
  Topology: Layer2
  CIDR: 10.101.0.0/24 (student-01), 10.201.0.0/24 (student-02), etc.
  Role: Corosync multicast heartbeat
  Multicast: Enabled (239.255.1.1)

Module 2 (MicroShift):
  Name: microshift-net
  Topology: Layer2
  CIDR: 10.102.0.0/24 (student-01), 10.202.0.0/24 (student-02), etc.
  Role: VRRP virtual IP failover
  Multicast: Enabled (224.0.0.18 for VRRP)

Module 3 (Two-Node OpenShift):
  Name: twonode-net
  Topology: Layer2
  CIDR: 10.103.0.0/24 (student-01), 10.203.0.0/24 (student-02), etc.
  Role: OpenShift cluster traffic
  Multicast: Disabled (unicast only)
```

### Network Isolation

Each UDN is namespace-scoped:
- **Student 01**: Uses 10.101.0.0/24 in `retail-edge-student-01-udn` namespace
- **Student 02**: Uses 10.201.0.0/24 in `retail-edge-student-02-udn` namespace
- Students cannot communicate cross-namespace

### Verification

```bash
# Check UDN creation
oc get userdefinednetwork -A

# Verify Layer 2 topology
oc get userdefinednetwork pacemaker-net -n retail-edge-student-01-udn -o yaml | grep topology
# Expected: topology: Layer2

# Test multicast support (from VM)
virtctl ssh cloud-user@rhel-ha-node1 -n retail-edge-student-01
$ ping -c 3 239.255.1.1
# Should NOT fail (multicast enabled)
```

### Troubleshooting

**Issue:** UDN stuck in "NotReady"

**Solution:**
```bash
# Check OVN pods
oc get pods -n openshift-ovn-kubernetes

# Check UDN events
oc describe userdefinednetwork pacemaker-net -n retail-edge-student-01-udn
```

**Issue:** VMs not getting IPs from UDN

**Solution:**
```bash
# Verify VM network attachment
oc get vm rhel-ha-node1 -n retail-edge-student-01 -o yaml | grep -A 5 "networks:"
# Should reference pacemaker-net

# Check VMI (running instance) IP
oc get vmi rhel-ha-node1 -n retail-edge-student-01 -o jsonpath='{.status.interfaces[1].ipAddress}'
# Expected: 10.101.0.20
```

---

## patch-showroom-terminals.sh

### Purpose

Injects student-specific environment variables into Showroom terminal pods to enable copy-paste commands in lab instructions.

### Usage

```bash
./scripts/patch-showroom-terminals.sh <student_count>
```

### Parameters

| Parameter | Description | Default | Valid Range |
|-----------|-------------|---------|-------------|
| `student_count` | Number of students | (required) | 1-50 |

### Example

```bash
# Patch terminals for 15 students
./scripts/patch-showroom-terminals.sh 15
```

### What It Does

For each student (01-15):
1. Creates ConfigMap `student-env` in `showroom-student-XX` namespace
2. Patches `showroom-terminal` Deployment to mount ConfigMap as environment variables
3. Restarts terminal pod to apply changes

### Environment Variables Injected

```bash
# Student identity
STUDENT_ID=01
STUDENT_NAMESPACE=retail-edge-student-01
STUDENT_UDN_NAMESPACE=retail-edge-student-01-udn
STUDENT_USER=student-01

# Cluster info
CLUSTER_DOMAIN=apps.cluster-ntq88.dynamic.redhatworkshops.io
CLUSTER_API=https://api.cluster-ntq88.dynamic.redhatworkshops.io:6443

# VM credentials
VM_USER=cloud-user
VM_PASSWORD=redhat

# Module 1 (Pacemaker)
RHEL_NODE1=rhel-ha-node1
RHEL_NODE2=rhel-ha-node2
PACEMAKER_NET=pacemaker-net
PACEMAKER_IP1=10.101.0.20
PACEMAKER_IP2=10.101.0.21
PACEMAKER_VIP=10.101.0.100

# Module 2 (MicroShift)
MICROSHIFT_GW_A=microshift-gw-a
MICROSHIFT_GW_B=microshift-gw-b
MICROSHIFT_VIP=10.102.0.100

# Module 3 (Two-Node OpenShift)
TWONODE_MASTER1=twonode-master1
TWONODE_MASTER2=twonode-master2
TWONODE_ARBITER=twonode-arbiter
```

### Usage in Workshop Instructions

Students can use these variables in terminal:

```bash
# Connect to VM
virtctl ssh $VM_USER@$RHEL_NODE1 -n $STUDENT_NAMESPACE

# Check namespace
oc get vms -n $STUDENT_NAMESPACE

# Ping pacemaker VIP
ping $PACEMAKER_VIP
```

### Verification

```bash
# Check ConfigMap exists
oc get configmap student-env -n showroom-student-01

# Verify environment variables in terminal
oc exec -n showroom-student-01 deployment/showroom-terminal -- env | grep STUDENT_
# Expected output: STUDENT_ID=01, STUDENT_NAMESPACE=retail-edge-student-01

# Test in actual terminal
# Open https://showroom-showroom-student-01.apps.<cluster>
# Terminal tab → Run: echo $STUDENT_NAMESPACE
# Should output: retail-edge-student-01
```

### Re-running the Script

Safe to run multiple times (idempotent):
```bash
# Update environment variables after cluster change
./scripts/patch-showroom-terminals.sh 10
# ConfigMaps updated, terminals restarted
```

### Troubleshooting

**Issue:** Variables not showing in terminal

**Solution:**
```bash
# Check deployment patch applied
oc get deployment showroom-terminal -n showroom-student-01 -o yaml | grep envFrom
# Expected: configMapRef: name: student-env

# Restart terminal manually
oc rollout restart deployment/showroom-terminal -n showroom-student-01
```

**Issue:** Script fails with "namespace not found"

**Solution:**
```bash
# Ensure Showroom deployed first
oc get namespaces | grep showroom-student
# Should show showroom-student-01, 02, etc.

# Deploy Showroom, then run patch
helm install retail-edge-ha ./helm/retail-edge-ha ...
./scripts/patch-showroom-terminals.sh 10
```

---

## validate-deployment.sh

### Purpose

Validates workshop deployment health and readiness across all components.

### Usage

```bash
./scripts/validate-deployment.sh <student_count>
```

### Parameters

| Parameter | Description | Default | Valid Range |
|-----------|-------------|---------|-------------|
| `student_count` | Number of students | (required) | 1-50 |

### Example

```bash
# Validate deployment for 20 students
./scripts/validate-deployment.sh 20
```

### Validation Checks

#### 1. Namespace Creation
```
✅ Checking student namespaces...
   Found: 20/20 workload namespaces (retail-edge-student-XX)
   Found: 20/20 UDN namespaces (retail-edge-student-XX-udn)
   Found: 20/20 Showroom namespaces (showroom-student-XX)
```

#### 2. ArgoCD Application Health
```
✅ Checking ArgoCD applications...
   retail-edge-ha: Synced, Healthy
   retail-edge-ha-showroom-01: Synced, Healthy
   retail-edge-ha-module1-01: Synced, Healthy
   ...
   Total: 61/61 applications healthy
```

#### 3. VirtualMachine Status
```
✅ Checking VirtualMachines...
   Module 1: 40/40 VMs created (20 students × 2 VMs)
   Module 2: 40/40 VMs created (20 students × 2 VMs)
   Module 3: 0/0 VMs created (module disabled)
   Total: 80/80 VMs in Stopped or Running state
```

#### 4. User Defined Networks
```
✅ Checking UDNs...
   pacemaker-net: 20/20 ready
   microshift-net: 20/20 ready
   twonode-net: 0/0 ready (module disabled)
   Total: 40/40 UDNs ready
```

#### 5. Showroom Availability
```
✅ Checking Showroom instances...
   Student 01: 4/4 pods running, route accessible (HTTP 200)
   Student 02: 4/4 pods running, route accessible (HTTP 200)
   ...
   Total: 20/20 Showroom instances healthy
```

#### 6. Resource Utilization
```
✅ Checking cluster resources...
   CPU: 320/1000 cores (32% utilized)
   Memory: 640/2048 GiB (31% utilized)
   Storage: 2.4/10 TiB (24% utilized)
   ✅ Sufficient capacity for current workload
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All checks passed |
| 1 | Missing namespaces |
| 2 | ArgoCD sync failures |
| 3 | VM creation failures |
| 4 | UDN not ready |
| 5 | Showroom issues |
| 6 | Resource exhaustion |

### Example Output (Success)

```
========================================
Retail Edge HA Workshop - Deployment Validation
Student Count: 20
========================================

✅ Namespaces: 60/60 created
✅ ArgoCD Apps: 61/61 healthy
✅ VirtualMachines: 80/80 ready
✅ User Defined Networks: 40/40 ready
✅ Showroom Instances: 20/20 accessible
✅ Cluster Resources: Sufficient

========================================
🎉 Workshop deployment validated successfully!
========================================

Next steps:
1. Access Showroom URLs for students
2. Students can start VMs with: virtctl start <vm-name> -n <namespace>
3. Monitor ArgoCD: oc get applications -n retail-edge-ha-gitops -w
```

### Example Output (Failure)

```
========================================
Retail Edge HA Workshop - Deployment Validation
Student Count: 20
========================================

✅ Namespaces: 60/60 created
❌ ArgoCD Apps: 58/61 healthy (3 degraded)
   - retail-edge-ha-showroom-15: OutOfSync
   - retail-edge-ha-showroom-18: Progressing
   - retail-edge-ha-module1-20: Degraded (pod crash)
⚠️  VirtualMachines: 75/80 ready (5 pending)
   - rhel-ha-node1 (student-12): Pending (DataVolume provisioning)
   - rhel-ha-node2 (student-15): Pending (DataVolume provisioning)
   ...
✅ User Defined Networks: 40/40 ready
✅ Showroom Instances: 19/20 accessible (student-15 route missing)
✅ Cluster Resources: Sufficient

========================================
❌ Workshop deployment has issues!
========================================

Troubleshooting:
1. Check ArgoCD application logs: oc describe application retail-edge-ha-showroom-15 -n retail-edge-ha-gitops
2. Check VM DataVolume status: oc get dv -n retail-edge-student-12
3. Force ArgoCD sync: oc patch application <app> -n retail-edge-ha-gitops --type merge -p '{"operation":{"sync":{}}}
```

### Integration with CI/CD

Use in pipelines for automated validation:

```yaml
# GitLab CI example
validate-workshop:
  stage: test
  script:
    - ./scripts/validate-deployment.sh 5
  only:
    - main
```

### Troubleshooting

**Issue:** Script reports "oc: command not found"

**Solution:**
```bash
# Ensure oc CLI installed and in PATH
which oc
# Install if missing: https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/
```

**Issue:** Validation hangs checking ArgoCD

**Solution:**
```bash
# Timeout after 60 seconds per application
# Increase timeout in script if needed
vim scripts/validate-deployment.sh
# Change: timeout=60 to timeout=120
```

---

## Script Development

### Adding New Scripts

Create new scripts following this template:

```bash
#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Script metadata
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

# Usage function
usage() {
  cat <<EOF
Usage: $SCRIPT_NAME <parameter>

Description:
  Brief description of what this script does

Parameters:
  parameter - Description of parameter (required/optional)

Example:
  $SCRIPT_NAME value
EOF
  exit 1
}

# Parameter validation
if [ $# -ne 1 ]; then
  usage
fi

PARAM=$1

# Main logic
echo "Processing $PARAM..."
# ... script body ...

echo "✅ Done!"
```

### Testing Scripts

```bash
# Dry-run mode (don't apply changes)
./scripts/generate-vm-manifests.sh 5 --dry-run

# Verbose output
./scripts/validate-deployment.sh 10 --verbose

# Debug mode
bash -x ./scripts/patch-showroom-terminals.sh 3
```

### Contributing

See [../CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines on:
- Bash best practices
- Error handling
- Documentation requirements
- Testing procedures

---

## Future Automation

Planned scripts (not yet implemented):

1. **generate-ignition-configs.sh** - Generate Bootstrap-in-Place ignition for Module 3
2. **build-vm-images.sh** - Build custom RHEL/RHCOS container disks with pre-installed packages
3. **export-student-progress.sh** - Backup student VM data before cluster maintenance
4. **scale-workshop.sh** - One-command scaling (add/remove students)
5. **health-check-cron.sh** - Automated health monitoring for production deployments

---

**Last Updated:** 2025-03-25 | **Maintainer:** Workshop Automation Team
