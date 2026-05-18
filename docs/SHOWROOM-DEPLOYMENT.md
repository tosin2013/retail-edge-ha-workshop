# Showroom Multi-Instance Deployment Guide

## Overview

This workshop deploys **one Showroom instance per student** to provide proper terminal isolation and student-specific environment variables.

Each student gets:
- Unique URL: `https://showroom-proxy-showroom-student-XX.apps.<cluster-domain>`
- Dedicated terminal with student-specific environment variables
- Isolated namespace: `showroom-student-XX`
- Access to their student namespace: `retail-edge-student-XX`

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│ Student 01                                                   │
│ https://showroom-proxy-showroom-student-01.apps...          │
│                                                              │
│ Namespace: showroom-student-01                              │
│   ├── showroom (UI)                                         │
│   ├── showroom-content (Antora documentation)              │
│   ├── showroom-proxy (nginx reverse proxy)                 │
│   └── showroom-terminal (wetty web terminal)               │
│        └── Environment Variables:                           │
│             STUDENT_ID=01                                   │
│             STUDENT_NAMESPACE=retail-edge-student-01        │
│             VM_USER=cloud-user                              │
│             RHEL_NODE1=rhel-ha-node1                        │
│             PACEMAKER_IP1=10.101.0.20                       │
│             ... (full list below)                           │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Student 02                                                   │
│ https://showroom-proxy-showroom-student-02.apps...          │
│                                                              │
│ (Same structure, student-specific environment variables)    │
│   STUDENT_ID=02                                             │
│   STUDENT_NAMESPACE=retail-edge-student-02                  │
│   ...                                                        │
└─────────────────────────────────────────────────────────────┘
```

## Deployment

Showroom instances are deployed automatically by the AgnosticD workload role as part of the hub cluster provisioning. No manual Helm commands are needed.

### One-Command Deployment

```bash
cd ~/Development/agnosticd-v2-vars/retail-edge-ha
NUM_STUDENTS=2 ./cluster-deploy.sh
```

This single script:
1. Provisions the hub OCP cluster on AWS
2. Installs OpenShift Virtualization, RHACM, cert-manager, OpenShift GitOps
3. Deploys the Helm app-of-apps via ArgoCD (which creates all Showroom instances)
4. Waits for all Showroom pods to be ready

### Verify Showroom is Running

```bash
KC=~/Development/agnosticd-v2-output/retail-ha/openshift-cluster_retail-ha_kubeconfig

# Check ArgoCD Showroom applications
oc --kubeconfig="$KC" get applications -n openshift-gitops | grep showroom

# Check pods per student
for i in 01 02; do
  echo "=== Student $i ==="
  oc --kubeconfig="$KC" get pods -n showroom-student-$i
done
```

Expected: 4/4 pods running per student (showroom, showroom-content, showroom-proxy, showroom-terminal).

### Get Student URLs

```bash
KC=~/Development/agnosticd-v2-output/retail-ha/openshift-cluster_retail-ha_kubeconfig

# Print all Showroom URLs
oc --kubeconfig="$KC" get routes -A \
  -o jsonpath='{range .items[*]}{.metadata.namespace}{": https://"}{.spec.host}{"\n"}{end}' \
  | grep showroom-student | sort
```

Or use the access info script (see below).

## Instructor Access Info Script

The `print-access-info.sh` script collects all environment credentials, URLs, and module-specific access details for every student and saves them to a single file.

```bash
cd ~/Development/agnosticd-v2-vars/retail-edge-ha
HUB_GUID=retail-ha NUM_STUDENTS=2 ./print-access-info.sh
```

Output is printed to stdout and saved to:
```
~/Development/agnosticd-v2-output/retail-ha/access-info.txt
```

Sample output:
```
============================================================
  Retail Edge HA Workshop — Environment Access Info
  Hub GUID:  retail-ha | Students: 2
============================================================

HUB CLUSTER
  Console:  https://console-openshift-console.apps.retail-ha...
  API:      https://api.retail-ha...:6443
  Login:    oc login ... -u kubeadmin -p <password>

------------------------------------------------------------
STUDENT 01
  Showroom:  https://showroom-proxy-showroom-student-01.apps...
  Namespace: retail-edge-student-01

  Module 1 — RHEL HA (Pacemaker)
    SSH node1: virtctl ssh cloud-user@rhel-ha-node1 -n retail-edge-student-01
    SSH node2: virtctl ssh cloud-user@rhel-ha-node2 -n retail-edge-student-01
    Password:  redhat

  Module 2 — MicroShift (VRRP)
    SSH gw-a:  virtctl ssh cloud-user@microshift-gw-a -n retail-edge-student-01
    SSH gw-b:  virtctl ssh cloud-user@microshift-gw-b -n retail-edge-student-01
    Password:  redhat

  Module 3 — Two-Node OCP (AWS)
    RHACM Cluster: student-01-twonode
    ...
```

## Available Environment Variables

Each Showroom terminal has access to these variables (automatically different per student):

```bash
STUDENT_ID              # 01, 02, 03, etc.
STUDENT_NAMESPACE       # retail-edge-student-XX
STUDENT_UDN_NAMESPACE   # retail-edge-student-XX-udn
STUDENT_USER            # student-XX

# Cluster info
CLUSTER_DOMAIN          # apps.<cluster-ingress-domain>
CLUSTER_API             # https://api.<cluster-domain>:6443

# VM credentials (shared across modules)
VM_USER                 # cloud-user
VM_PASSWORD             # redhat

# Module 1: Pacemaker HA
RHEL_NODE1              # rhel-ha-node1
RHEL_NODE2              # rhel-ha-node2
PACEMAKER_NET           # pacemaker-net
PACEMAKER_IP1           # 10.101.0.20
PACEMAKER_IP2           # 10.101.0.21
PACEMAKER_VIP           # 10.101.0.100

# Module 2: MicroShift VRRP
MICROSHIFT_GWA          # microshift-gw-a
MICROSHIFT_GWB          # microshift-gw-b
MICROSHIFT_NET          # microshift-net
MICROSHIFT_GWA_IP       # 10.102.0.20
MICROSHIFT_GWB_IP       # 10.102.0.21
MICROSHIFT_VIP          # 10.102.0.100

# Module 3: Two-Node OCP (AWS)
MODULE3_CLUSTER         # student-XX-twonode  (RHACM managed cluster name)
```

## Usage in Workshop Instructions

Students use these variables in terminal commands:

```bash
# Module 1 — SSH into Pacemaker node
virtctl ssh $VM_USER@$RHEL_NODE1 -n $STUDENT_NAMESPACE

# Module 1 — Check Pacemaker status
virtctl ssh $VM_USER@$RHEL_NODE1 -n $STUDENT_NAMESPACE -- sudo pcs status

# Module 2 — SSH into MicroShift gateway
virtctl ssh $VM_USER@$MICROSHIFT_GWA -n $STUDENT_NAMESPACE

# Module 3 — Access two-node cluster via RHACM console
# Navigate to RHACM → Infrastructure → Clusters → student-XX-twonode
```

## Scaling to More Students

Update `NUM_STUDENTS` in `cluster-deploy.sh` or pass it as an environment variable:

```bash
NUM_STUDENTS=25 ./cluster-deploy.sh
```

The Helm chart creates one Showroom app and one student namespace per student automatically based on `students.count` in `helm/retail-edge-ha/values.yaml`.

**Resource requirements per student (Showroom only):**
- Pods: 4
- Memory: ~1 GB
- CPU: ~1.2 cores

For 25 students: ~100 Showroom pods, ~25 GB memory, ~30 CPU cores (Showroom only; VM resources are additional).

## Troubleshooting

### Showroom pods not starting

```bash
KC=~/Development/agnosticd-v2-output/retail-ha/openshift-cluster_retail-ha_kubeconfig

# Check events
oc --kubeconfig="$KC" get events -n showroom-student-01 --sort-by='.lastTimestamp'

# Check pod logs
oc --kubeconfig="$KC" logs -n showroom-student-01 deployment/showroom-content
```

### ArgoCD Showroom applications stuck "OutOfSync" or "Missing"

The most common cause is the ArgoCD service account lacking RBAC on the Showroom namespaces. Verify the namespace label:

```bash
KC=~/Development/agnosticd-v2-output/retail-ha/openshift-cluster_retail-ha_kubeconfig

oc --kubeconfig="$KC" get namespace showroom-student-01 \
  -o jsonpath='{.metadata.labels.argocd\.argoproj\.io/managed-by}'
# Should output: openshift-gitops
```

If the label is missing, re-run the workload:

```bash
cd ~/Development/agnosticd-v2-vars/retail-edge-ha
./deploy.sh
```

### Environment variables not in terminal

Environment variables are injected by the Showroom Helm chart via a ConfigMap. If a terminal is missing variables, check the ArgoCD Showroom config application:

```bash
KC=~/Development/agnosticd-v2-output/retail-ha/openshift-cluster_retail-ha_kubeconfig

oc --kubeconfig="$KC" get application retail-edge-ha-showroom-config -n openshift-gitops
oc --kubeconfig="$KC" get configmap student-env -n showroom-student-01
```

### Terminal CLI tools

The Showroom terminal image (`wetty`) includes standard shell utilities. OpenShift CLI tools (`oc`, `virtctl`) are pre-installed in the terminal image configured by the workshop Helm chart. If a tool is missing, check the terminal image in `helm/retail-edge-ha/values.yaml`.
