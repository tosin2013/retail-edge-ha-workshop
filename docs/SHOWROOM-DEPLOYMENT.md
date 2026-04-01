# Showroom Multi-Instance Deployment Guide

## Overview

This workshop deploys **one Showroom instance per student** to provide proper terminal isolation and student-specific environment variables.

Each student gets:
- Unique URL: `https://showroom-proxy-showroom-student-XX.apps...`
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
│             ... (14 total variables)                        │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│ Student 02                                                   │
│ https://showroom-proxy-showroom-student-02.apps...          │
│                                                              │
│ (Same structure, different environment variables)            │
│   STUDENT_ID=02                                             │
│   STUDENT_NAMESPACE=retail-edge-student-02                  │
│   ...                                                        │
└─────────────────────────────────────────────────────────────┘
```

## Deployment Steps

### 1. Deploy via ArgoCD (Recommended)

The parent ArgoCD application will create child applications for each student:

```bash
# Sync parent application
oc patch application retail-edge-ha -n openshift-gitops \
  --type=merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'

# Wait for child applications to be created
oc get applications -n openshift-gitops | grep showroom
# Should show: retail-edge-ha-showroom-01 through -05
```

**Note:** ArgoCD sync may be slow. If applications remain in "OutOfSync/Missing" for >10 minutes, use manual deployment below.

### 2. Manual Deployment (Faster, for Development)

Deploy Showroom instances directly using Helm:

```bash
# Deploy all 5 student instances
for i in 01 02 03 04 05; do
  echo "Deploying showroom-student-$i..."
  helm template showroom-$i showroom/showroom --version 0.4.9 \
    --set namespace.name=showroom-student-$i \
    --set content.repoUrl=https://github.com/tosin2013/retail-edge-ha-workshop.git \
    --set content.repoRef=main \
    --set content.antoraPlaybook=site.yml \
    --set deployer.domain=apps.cluster-cfz7p.dynamic.redhatworkshops.io \
    --set deployer.ingress.name=showroom-student-$i \
    --set terminal.image=docker.io/wettyoss/wetty:latest \
    | oc apply -f -
done
```

### 3. Patch Terminal Deployments (Required)

After deployment, inject student environment variables into terminal pods:

```bash
# Run the patch script
./scripts/patch-showroom-terminals.sh 5

# Verify environment variables are available
oc exec -n showroom-student-01 deployment/showroom-terminal -- env | grep STUDENT_
```

**Why is this needed?**
The Showroom 0.4.9 chart doesn't natively support injecting custom environment variables into the terminal pod. Our script patches each terminal deployment to mount the `student-env` ConfigMap as environment variables.

## Verification

### Check Deployment Status

```bash
# Check all Showroom namespaces
oc get namespaces | grep showroom-student

# Check pods in each namespace
for i in 01 02 03 04 05; do
  echo "=== Student $i ==="
  oc get pods -n showroom-student-$i
done
```

Expected output: 4/4 pods running per student (showroom, showroom-content, showroom-proxy, showroom-terminal)

### Verify Environment Variables

```bash
# Student 01
oc exec -n showroom-student-01 deployment/showroom-terminal -- sh -c 'echo "Student: $STUDENT_ID, Namespace: $STUDENT_NAMESPACE"'
# Output: Student: 01, Namespace: retail-edge-student-01

# Student 02
oc exec -n showroom-student-02 deployment/showroom-terminal -- sh -c 'echo "Student: $STUDENT_ID, Namespace: $STUDENT_NAMESPACE"'
# Output: Student: 02, Namespace: retail-edge-student-02
```

### Access Workshop URLs

```bash
# Get all student URLs
for i in 01 02 03 04 05; do
  echo "Student $i: https://$(oc get route -n showroom-student-$i -o jsonpath='{.items[0].spec.host}')"
done
```

## Available Environment Variables

Each terminal has access to these variables (automatically different per student):

```bash
STUDENT_ID              # 01, 02, 03, etc.
STUDENT_NAMESPACE       # retail-edge-student-XX
STUDENT_UDN_NAMESPACE   # retail-edge-student-XX-udn
STUDENT_USER            # student-XX

# Cluster info
CLUSTER_DOMAIN          # apps.cluster-cfz7p.dynamic.redhatworkshops.io
CLUSTER_API             # https://api.cluster-cfz7p.dynamic.redhatworkshops.io:6443

# VM credentials
VM_USER                 # cloud-user
VM_PASSWORD             # redhat

# Module 1: Pacemaker HA
RHEL_NODE1             # rhel-ha-node1
RHEL_NODE2             # rhel-ha-node2
PACEMAKER_NET          # pacemaker-net
PACEMAKER_IP1          # 10.101.0.20
PACEMAKER_IP2          # 10.101.0.21
PACEMAKER_VIP          # 10.101.0.100
```

## Usage in Workshop Instructions

Students can use these variables in terminal commands:

```bash
# Connect to VM (when VMs are deployed)
virtctl ssh $VM_USER@$RHEL_NODE1 -n $STUDENT_NAMESPACE

# Check student namespace resources
oc get vms -n $STUDENT_NAMESPACE

# View pacemaker cluster status
virtctl ssh $VM_USER@$RHEL_NODE1 -n $STUDENT_NAMESPACE -- \
  sudo pcs status
```

## Scaling to More Students

To deploy for more students (e.g., 25):

```bash
# Update values.yaml
students:
  count: 25

# Redeploy via ArgoCD or manually deploy 25 instances
# Then patch all 25 terminals
./scripts/patch-showroom-terminals.sh 25
```

## Troubleshooting

### Terminal doesn't have environment variables

```bash
# Check if ConfigMap exists
oc get configmap student-env -n showroom-student-01

# Re-run patch script
./scripts/patch-showroom-terminals.sh 5

# Verify patch was applied
oc get deployment showroom-terminal -n showroom-student-01 \
  -o jsonpath='{.spec.template.spec.containers[0].envFrom}'
```

### Pods not starting

```bash
# Check events
oc get events -n showroom-student-01 --sort-by='.lastTimestamp'

# Check pod logs
oc logs -n showroom-student-01 deployment/showroom-content
```

### ArgoCD applications stuck "OutOfSync"

```bash
# Delete and recreate applications
oc delete application retail-edge-ha-showroom-01 -n openshift-gitops
helm template retail-edge-ha ./helm/retail-edge-ha --show-only templates/apps/showroom-app.yaml | oc apply -f -
```

## Resource Usage

Per student (5 students total = 20 pods, ~5GB memory):
- **Pods:** 4 (showroom, content, proxy, terminal)
- **Memory:** ~1GB total
  - showroom: 64Mi
  - showroom-content: 64Mi
  - showroom-proxy: 256Mi
  - showroom-terminal: 256Mi
- **CPU:** ~1.2 cores total
  - showroom: 100m
  - showroom-content: 100m
  - showroom-proxy: 500m
  - showroom-terminal: 500m

For 50 students: ~200 pods, ~50GB memory, ~60 CPU cores (requires large cluster).
