# Bookbag Workshop Delivery

This directory contains the containerized workshop content delivery system using [Bookbag (Homeroom)](https://github.com/openshift-homeroom/workshop-dashboard).

## Overview

Bookbag provides:
- Web-based lab guide with embedded terminal
- Per-student variable injection
- Command execution with a single click
- Syntax highlighting for code blocks
- Collapsible troubleshooting sections

## Structure

```
bookbag/
├── Dockerfile                   # Container build definition
├── .s2i/environment            # Build-time environment variables
├── workshop/
│   ├── workshop.yaml           # Workshop configuration and variables
│   ├── modules.yaml            # Module definitions
│   └── content/                # AsciiDoc lab guides
│       ├── introduction.adoc
│       ├── module1-pacemaker.adoc
│       ├── module2-microshift.adoc
│       ├── module3-twonode.adoc
│       ├── module4-chaos.adoc
│       └── conclusion.adoc
└── deploy/
    ├── build.yaml              # BuildConfig for container image
    └── deployment.yaml         # Student deployment template
```

## Building the Bookbag Image

### Option 1: OpenShift BuildConfig

Create the build infrastructure:

```bash
oc new-project retail-edge-workshop

oc apply -f deploy/build.yaml
```

Trigger a build:

```bash
oc start-build retail-edge-ha-bookbag -n retail-edge-workshop
```

Monitor the build:

```bash
oc logs -f bc/retail-edge-ha-bookbag -n retail-edge-workshop
```

### Option 2: Local Docker Build

Build locally and push to a registry:

```bash
cd bookbag/
docker build -t quay.io/<your-username>/retail-edge-ha-bookbag:latest .
docker push quay.io/<your-username>/retail-edge-ha-bookbag:latest
```

Update `deploy/deployment.yaml` to reference your image.

## Deploying for Students

### Single Student Deployment

Deploy Bookbag for student-01:

```bash
oc apply -f deploy/deployment.yaml -n retail-edge-student-01
```

Get the Bookbag URL:

```bash
oc get route bookbag -n retail-edge-student-01 -o jsonpath='{.spec.host}'
```

Access the workshop at: `https://<route-url>/workshop/`

Default credentials:
- Username: `student-01`
- Password: `openshift`

### Multi-Student Deployment

Use the generation script to create Bookbag deployments for multiple students:

```bash
../scripts/generate-bookbag-deployments.sh 50
```

This creates:
- `bookbag-student-01.yaml` through `bookbag-student-50.yaml`
- Each with unique environment variables
- Namespace-specific deployments

Apply for all students:

```bash
for i in {01..50}; do
  oc apply -f bookbag-student-$i.yaml -n retail-edge-student-$i
done
```

## Workshop Variables

Variables are automatically injected into the lab guide from environment variables:

| Variable | Example Value | Usage |
|----------|---------------|-------|
| `STUDENT_ID` | `01` | Student identifier |
| `STUDENT_NAMESPACE` | `retail-edge-student-01` | Workload namespace |
| `STUDENT_UDN_NAMESPACE` | `retail-edge-student-01-udn` | UDN namespace |
| `CLUSTER_DOMAIN` | `apps.cluster-ntq88...` | OpenShift apps domain |
| `CLUSTER_API` | `https://api.cluster-ntq88...` | API server URL |
| `VM_USER` | `cloud-user` | VM SSH username |
| `VM_PASSWORD` | `redhat` | VM SSH password |
| `RHEL_NODE1` | `rhel-ha-node1` | Module 1 VM name |
| `MICROSHIFT_GW_A` | `microshift-gw-a` | Module 2 VM name |
| `TWONODE_MASTER1` | `twonode-master1` | Module 3 VM name |

Variables are referenced in AsciiDoc using `%VARIABLE_NAME%`:

```asciidoc
[source,bash,role=execute]
----
virtctl ssh %VM_USER%@%RHEL_NODE1% -n %STUDENT_NAMESPACE%
----
```

## AsciiDoc Features

### Executable Commands

Mark command blocks with `role=execute` for one-click execution:

```asciidoc
[source,bash,role=execute]
----
oc get pods -n %STUDENT_NAMESPACE%
----
```

### Collapsible Sections

Create collapsible troubleshooting sections:

```asciidoc
[%collapsible]
====
*Problem:* VMs not starting

*Solution:*
[source,bash]
----
oc describe vm rhel-ha-node1 -n %STUDENT_NAMESPACE%
----
====
```

### Links

Open links in new tabs:

```asciidoc
https://console-%CLUSTER_DOMAIN%[OpenShift Web Console,window=_blank]
```

### Code Highlighting

```asciidoc
[source,yaml]
----
apiVersion: v1
kind: Pod
...
----
```

## Customization

### Update Workshop Content

1. Edit AsciiDoc files in `workshop/content/`
2. Rebuild the container image
3. Restart Bookbag deployments:

```bash
oc rollout restart deployment/bookbag -n retail-edge-student-01
```

### Add a New Module

1. Create `workshop/content/moduleX-name.adoc`
2. Update `workshop/modules.yaml`:

```yaml
modules:
  moduleX-name:
    name: "Module X: Name"
    exit_sign: Next Module
```

3. Update `workshop/workshop.yaml`:

```yaml
modules:
  activate:
  - introduction
  - moduleX-name
  - conclusion
```

4. Rebuild and redeploy.

### Change Variables

Update `deploy/deployment.yaml` environment variables:

```yaml
env:
- name: STUDENT_ID
  value: "02"  # Change for student-02
- name: CUSTOM_VAR
  value: "my-value"  # Add custom variable
```

Reference in AsciiDoc:

```asciidoc
Your custom value: %CUSTOM_VAR%
```

## Troubleshooting

### Bookbag Pod Not Starting

```bash
oc get pods -n retail-edge-student-01
oc describe pod bookbag-<pod-id> -n retail-edge-student-01
oc logs bookbag-<pod-id> -n retail-edge-student-01
```

### Workshop Content Not Loading

Check the build logs:

```bash
oc logs -f bc/retail-edge-ha-bookbag -n retail-edge-workshop
```

Verify the image is up to date:

```bash
oc get is retail-edge-ha-bookbag -n retail-edge-workshop
```

### Environment Variables Not Injected

Verify deployment environment:

```bash
oc set env deployment/bookbag --list -n retail-edge-student-01
```

Restart the deployment:

```bash
oc rollout restart deployment/bookbag -n retail-edge-student-01
```

### 404 Not Found on Workshop URL

Ensure you're accessing `/workshop/` (with trailing slash):

```bash
https://<route-url>/workshop/
```

## Integration with ArgoCD

The Bookbag deployment is included in the Helm chart's App of Apps pattern:

```yaml
# helm/retail-edge-ha/templates/apps/bookbag-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bookbag
spec:
  syncWave: 3  # Deploy after VMs
```

ArgoCD will:
1. Build the Bookbag image
2. Deploy per-student instances
3. Sync workshop content automatically

## Performance Considerations

- **Image Size**: ~500MB (based on workshop-dashboard base image)
- **Memory Usage**: 512Mi request, 1Gi limit per student
- **CPU Usage**: 250m request, 500m limit per student
- **Startup Time**: 10-15 seconds for pod readiness

For 50 students:
- **Total Memory**: 25Gi requests, 50Gi limits
- **Total CPU**: 12.5 cores requests, 25 cores limits

## Security

- **ServiceAccount**: Each Bookbag has a dedicated ServiceAccount
- **RBAC**: Bound to `edit` role in student namespace
- **Authentication**: Basic auth with per-student credentials
- **Network**: Accessed via OpenShift Route (TLS edge termination)

## References

- [Homeroom Workshop Dashboard](https://github.com/openshift-homeroom/workshop-dashboard)
- [AsciiDoc Syntax Quick Reference](https://docs.asciidoctor.org/asciidoc/latest/syntax-quick-reference/)
- [OpenShift BuildConfig](https://docs.openshift.com/container-platform/latest/cicd/builds/understanding-buildconfigs.html)
