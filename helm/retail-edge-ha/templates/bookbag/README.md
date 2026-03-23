# Bookbag Helm Templates

This directory contains Helm templates for deploying Bookbag (Homeroom) workshop content to each student namespace.

## Templates

### namespace.yaml
Creates the build namespace for Bookbag BuildConfig and ImageStream.

**Resources:**
- `Namespace`: `retail-edge-workshop` (configurable via `bookbag.build.namespace`)

### buildconfig.yaml
Creates the OpenShift BuildConfig to build the Bookbag container image from GitHub.

**Resources:**
- `ImageStream`: Stores the built workshop image
- `BuildConfig`: Builds from `bookbag/` directory in GitHub repo

**Triggers:**
- ConfigChange: Rebuilds when BuildConfig changes
- ImageChange: Rebuilds when base image updates

### deployment.yaml
Creates per-student Bookbag deployments with personalized environment variables.

**Resources (per student):**
- `ServiceAccount`: For accessing student namespace resources
- `RoleBinding`: Grants `edit` role to Bookbag SA
- `Deployment`: Runs the workshop dashboard container
- `Service`: ClusterIP service for the dashboard
- `Route`: Exposes dashboard via HTTPS

**Environment Variables:**
All workshop variables are injected from `values.yaml`:
- Student-specific: `STUDENT_ID`, `STUDENT_NAMESPACE`, etc.
- Cluster info: `CLUSTER_DOMAIN`, `CLUSTER_API`
- Module 1: `RHEL_NODE1`, `PACEMAKER_VIP`, etc.
- Module 2: `MICROSHIFT_GW_A`, `MICROSHIFT_VIP`, etc.
- Module 3: `TWONODE_MASTER1`, `TWONODE_ARBITER`, etc.

## Rendering

**Test rendering for 5 students:**
```bash
helm template retail-edge-ha ./helm/retail-edge-ha --set students.count=5 > /tmp/rendered.yaml
grep -c "kind: Deployment" /tmp/rendered.yaml  # Should be 5
```

**Validate generated environment variables:**
```bash
helm template retail-edge-ha ./helm/retail-edge-ha --set students.count=1 | \
  grep -A 100 "kind: Deployment" | \
  grep -A 50 "env:"
```

## Configuration

All configuration is in `values.yaml`:

```yaml
bookbag:
  enabled: true
  build:
    namespace: "retail-edge-workshop"
  image:
    repository: "image-registry.openshift-image-registry.svc:5000/retail-edge-workshop/retail-edge-ha-bookbag"
    tag: "latest"
  resources:
    requests:
      cpu: "250m"
      memory: "512Mi"
```

## Deployment

### Via Helm

```bash
helm install retail-edge-ha ./helm/retail-edge-ha \
  --set students.count=5 \
  --set global.clusterDomain=apps.your-cluster.com \
  --set global.clusterApiUrl=https://api.your-cluster.com:6443
```

### Via ArgoCD (Recommended)

The parent ArgoCD Application automatically renders these templates:

```bash
oc apply -f helm/retail-edge-ha/templates/argocd-app.yaml
```

ArgoCD will:
1. Render Helm chart with current `values.yaml`
2. Create build namespace
3. Start BuildConfig (builds image from GitHub)
4. Deploy Bookbag for each student
5. Create Routes for web access

## Access

After deployment, students access their lab guide at:

```
https://bookbag-retail-edge-student-01.<cluster-domain>/workshop/
```

**Login:**
- Username: `student-01`
- Password: `openshift` (configurable via `bookbag.auth.password`)

## Customization

### Change Image Registry

To use external registry (e.g., Quay.io):

```yaml
bookbag:
  image:
    repository: "quay.io/your-org/retail-edge-ha-bookbag"
```

### Adjust Resources

For high-traffic workshops:

```yaml
bookbag:
  resources:
    requests:
      cpu: "500m"
      memory: "1Gi"
  replicas: 2  # Multiple pods per student
```

### Update Variables

To change VM names or IPs, update `values.yaml` sections:

```yaml
virtualMachines:
  module1:
    vmNames:
      node1: "custom-node1"

networking:
  module1:
    node1Ip: "192.168.1.10"
```

These automatically propagate to Bookbag environment variables.

## Troubleshooting

### Bookbag Not Deploying

```bash
# Check if enabled
helm get values retail-edge-ha | grep bookbag -A 5

# Verify templates render
helm template retail-edge-ha ./helm/retail-edge-ha | grep -A 10 "kind: Deployment"
```

### Build Failing

```bash
# Check BuildConfig
oc get bc -n retail-edge-workshop
oc logs -f bc/retail-edge-ha-bookbag -n retail-edge-workshop

# Trigger manual build
oc start-build retail-edge-ha-bookbag -n retail-edge-workshop
```

### Environment Variables Not Injected

```bash
# Verify deployment has env vars
oc get deployment bookbag -n retail-edge-student-01 -o yaml | grep -A 50 env:

# Check values.yaml has required sections
grep -A 3 "vmNames:" helm/retail-edge-ha/values.yaml
```

## Integration with Workshop Content

The Bookbag templates reference variables defined in `/bookbag/workshop/workshop.yaml`.

**Variable flow:**
1. `values.yaml` defines infrastructure (VM names, IPs)
2. Helm templates inject as environment variables
3. Bookbag runtime substitutes `%VARIABLE_NAME%` in AsciiDoc
4. Students see personalized content

**Example:**

`values.yaml`:
```yaml
virtualMachines:
  module1:
    vmNames:
      node1: "rhel-ha-node1"
```

`deployment.yaml`:
```yaml
- name: RHEL_NODE1
  value: "{{ $.Values.virtualMachines.module1.vmNames.node1 }}"
```

`module1-pacemaker.adoc`:
```asciidoc
virtctl start %RHEL_NODE1% -n %STUDENT_NAMESPACE%
```

Student sees:
```bash
virtctl start rhel-ha-node1 -n retail-edge-student-01
```
