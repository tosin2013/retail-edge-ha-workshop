# ADR-0004: Bookbag for Workshop Content Delivery

## Status

**Accepted** - 2026-03-22

## Context and Problem Statement

The Retail Edge HA Workshop requires delivering comprehensive lab instructions to 11-50 students covering 4 modules with hands-on exercises. Each module includes:
- Architecture overview and concepts
- Step-by-step configuration instructions
- CLI commands to execute
- Validation and testing procedures
- Troubleshooting guidance

**Key Requirements**:
1. **Web-Accessible**: Students should access from any device (laptop, tablet)
2. **Personalized**: Each student sees their own namespace, cluster URL, credentials
3. **Version Controlled**: Lab guide updates should be easy to deploy
4. **Professional Experience**: Workshop should feel polished, not DIY
5. **Embedded Terminal**: Bonus if students can run commands directly in browser

**Question**: How should we deliver the workshop lab guide and instructions to students?

## Decision Drivers

- **Accessibility**: No software installation required for students
- **Personalization**: Variables like `STUDENT_NAMESPACE` auto-injected
- **Maintainability**: Single update affects all students instantly
- **Professional UX**: Consistent with Red Hat training materials
- **GitOps Alignment**: Content versioned in Git, deployed via ArgoCD

## Considered Options

### Option 1: Static Markdown in GitHub Repository
**Delivery**: Students read README.md and module files directly from GitHub

**Pros**:
- Simple, no infrastructure required
- Familiar to developers
- Easy to edit (just commit Markdown)

**Cons**:
- ❌ **No Personalization**: Students manually replace `<your-namespace>` placeholders
- ❌ **No Terminal**: Students need separate SSH/oc CLI setup
- ❌ **Fragmented UX**: Jump between GitHub and terminal
- ❌ **No Navigation**: Long single-page scroll or complex file tree
- ❌ **Not Professional**: Feels like a GitHub README, not a training course

**Verdict**: Rejected - poor user experience

### Option 2: Google Docs or Confluence Wiki
**Delivery**: Hosted documentation with web access

**Pros**:
- Web-accessible
- Familiar collaboration tools
- WYSIWYG editing

**Cons**:
- ❌ **Not Git-Versioned**: Changes not tracked in VCS
- ❌ **No Personalization**: Still requires manual placeholder replacement
- ❌ **No Terminal Integration**: Separate CLI required
- ❌ **External Dependency**: Requires Google/Atlassian accounts
- ❌ **Not GitOps**: Cannot deploy via ArgoCD

**Verdict**: Rejected - doesn't integrate with GitOps workflow

### Option 3: Jupyter Notebooks
**Delivery**: JupyterHub with notebook cells for instructions and code

**Pros**:
- ✅ Web-accessible
- ✅ Embedded terminal (via kernels)
- ✅ Interactive code execution

**Cons**:
- ⚠️ **Steep Learning Curve**: Students need to understand notebook interface
- ⚠️ **Not Document-Focused**: Optimized for data science, not instructions
- ⚠️ **Complex Setup**: JupyterHub deployment, kernel management
- ⚠️ **Not Standard**: Not used in Red Hat workshop ecosystem

**Verdict**: Rejected - over-engineered for documentation use case

### Option 4: Bookbag (Homeroom Framework) (SELECTED)
**Delivery**: Containerized workshop guide with embedded web terminal

**Technology**: [OpenShift Homeroom](https://github.com/openshift-homeroom/homeroom-workshop-dashboard)

**Example**:
```yaml
# workshop.yaml
name: Retail Edge HA Workshop
modules:
  activate:
  - module1-rhel-ha
  - module2-microshift
vars:
  - name: STUDENT_NAMESPACE
    value: retail-edge-student-01
  - name: CLUSTER_DOMAIN
    value: apps.cluster-ntq88.dynamic.redhatworkshops.io
```

**Pros**:
- ✅ **Web-Accessible**: Students visit a URL, nothing to install
- ✅ **Personalized**: Variables auto-injected (`%STUDENT_NAMESPACE%` → `retail-edge-student-01`)
- ✅ **Embedded Terminal**: Web terminal in-browser, auto-logged-in to OpenShift
- ✅ **Professional UX**: Used by Red Hat training and RHPDS workshops
- ✅ **Git-Versioned**: Content in AsciiDoc files, versioned in Git
- ✅ **Container-Based**: Deployed via ArgoCD, scales to 50+ students
- ✅ **Navigation**: Left sidebar with module list, progress tracking
- ✅ **Red Hat Standard**: Proven technology used across field workshops

**Cons**:
- ⚠️ **Container Build**: Requires building Bookbag image (automation needed)
- ⚠️ **AsciiDoc Learning**: Content authors need to learn AsciiDoc format
   - *Mitigation*: AsciiDoc is similar to Markdown, easy to learn
   - *Mitigation*: Templates and examples provided

**Verdict**: Selected - industry-standard workshop delivery platform

## Decision

**We will use Bookbag (OpenShift Homeroom)** for workshop content delivery.

### Implementation

**Architecture**:
```
Bookbag Deployment
├── Container Image: quay.io/tosin2013/retail-edge-bookbag:latest
├── Content: AsciiDoc files in content/workshop/
├── Route: https://bookbag-retail-edge-bookbag.apps.cluster.com
└── Terminal: Embedded web terminal with oc CLI

Student Access:
1. Visit Bookbag URL
2. See personalized instructions with their namespace/credentials
3. Click "Terminal" tab to run commands
4. Navigate modules via left sidebar
```

**Directory Structure**:
```
content/workshop/
├── workshop.yaml          # Workshop definition
├── modules.yaml           # Module structure
├── content/
│   ├── index.adoc         # Landing page
│   └── modules/
│       ├── module1-rhel-ha/
│       │   ├── overview.adoc
│       │   ├── setup-cluster.adoc
│       │   └── test-failover.adoc
│       ├── module2-microshift/
│       ├── module3-twonode/
│       └── module4-chaos/
└── Dockerfile             # Bookbag image build
```

**workshop.yaml**:
```yaml
name: Retail Edge High-Availability Workshop
description: Learn to deploy and test HA architectures for retail edge environments
vars:
  - name: CLUSTER_DOMAIN
    desc: OpenShift cluster domain
    value: apps.cluster-ntq88.dynamic.redhatworkshops.io
  - name: STUDENT_NAMESPACE
    desc: Your student namespace
    value: retail-edge-student-01
  - name: STUDENT_USER
    desc: Your student username
    value: student-01
modules:
  activate:
  - introduction
  - module1-rhel-ha
  - module2-microshift
  - module3-twonode
  - module4-chaos
  - conclusion
```

**AsciiDoc Variable Substitution**:
```asciidoc
= Module 1: RHEL HA with Pacemaker

== Login to Your Namespace

Your assigned namespace is: `%STUDENT_NAMESPACE%`

[source,bash,role=execute]
----
oc project %STUDENT_NAMESPACE%
----

Your VMs will be named:
* `rhel-ha-node1`
* `rhel-ha-node2`
```

**Rendered for Student 05**:
```
Your assigned namespace is: retail-edge-student-05

$ oc project retail-edge-student-05
```

**Dockerfile**:
```dockerfile
FROM quay.io/redhat-gpte/bookbag:latest

USER root

COPY content/ /opt/app-root/workshop/

RUN chown -R 1001:0 /opt/app-root/workshop && \
    chmod -R g=u /opt/app-root/workshop

USER 1001

LABEL name="retail-edge-ha-bookbag" \
      version="1.0" \
      description="Retail Edge HA Workshop Lab Guide"
```

**Deployment**:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bookbag
  namespace: retail-edge-bookbag
spec:
  replicas: 1
  selector:
    matchLabels:
      app: bookbag
  template:
    metadata:
      labels:
        app: bookbag
    spec:
      containers:
      - name: bookbag
        image: quay.io/tosin2013/retail-edge-bookbag:latest
        env:
        - name: WORKSHOP_VARS
          value: |
            CLUSTER_DOMAIN=apps.cluster-ntq88.dynamic.redhatworkshops.io
            STUDENT_NAMESPACE=retail-edge-student-01
        ports:
        - containerPort: 10080
          name: http
```

## Consequences

### Positive

✅ **Zero Setup for Students**: Visit URL, start learning immediately
✅ **Personalized Experience**: Each student sees their own namespace, credentials
✅ **Embedded Terminal**: No SSH client needed, run commands in browser
✅ **Professional UX**: Matches Red Hat training standards
✅ **Git-Versioned Content**: All lab instructions in Git, reviewable via PR
✅ **Container-Based Delivery**: Deploy/update via ArgoCD GitOps
✅ **Scalable**: Single Bookbag pod serves all students (stateless)
✅ **Offline-Capable**: Workshop content cached in container image

### Negative

❌ **Container Build Required**: Must build/push image for content updates
   - *Mitigation*: Automate via GitHub Actions or Tekton pipeline
   - *Example*:
     ```yaml
     # .github/workflows/build-bookbag.yaml
     name: Build Bookbag
     on:
       push:
         paths:
           - 'content/workshop/**'
     jobs:
       build:
         runs-on: ubuntu-latest
         steps:
           - uses: actions/checkout@v2
           - name: Build and push
             run: |
               cd content/workshop
               podman build -t quay.io/tosin2013/retail-edge-bookbag:$GITHUB_SHA .
               podman push quay.io/tosin2013/retail-edge-bookbag:$GITHUB_SHA
     ```

❌ **AsciiDoc Learning Curve**: Content authors need to learn AsciiDoc
   - *Mitigation*: Provide AsciiDoc cheat sheet and templates
   - *Reality*: AsciiDoc is very similar to Markdown, easy transition

❌ **Single Pod Bottleneck**: If Bookbag pod dies, all students lose access
   - *Mitigation*: Set `replicas: 3` for high availability
   - *Mitigation*: Bookbag is stateless, pod restart is instant

### Neutral

⚖️ **Image Registry Dependency**: Requires Quay.io or internal registry
   - This is standard for container-based deployments

⚖️ **Web Terminal Limitations**: Not as powerful as native terminal
   - Sufficient for workshop commands (oc, virtctl, ssh)

## Validation

**Test Cases**:

1. **Variable Substitution Test**:
   ```bash
   # Build Bookbag image
   cd content/workshop
   podman build -t bookbag-test .

   # Deploy and access
   oc new-app --image=bookbag-test
   oc create route edge --service=bookbag-test

   # Check rendered content
   curl https://bookbag-test-route/index.html | grep "retail-edge-student-"
   # Expected: Variables replaced with actual values
   ```

2. **Multi-User Test**:
   ```bash
   # Access Bookbag as student-01
   curl https://bookbag?user=student-01 | grep STUDENT_NAMESPACE
   # Expected: retail-edge-student-01

   # Access as student-02
   curl https://bookbag?user=student-02 | grep STUDENT_NAMESPACE
   # Expected: retail-edge-student-02
   ```

3. **Terminal Integration Test**:
   ```bash
   # Access Bookbag web terminal
   # Run: oc project
   # Expected: Already logged in, no authentication required
   ```

## Content Development Workflow

### 1. Write Content (AsciiDoc)
```asciidoc
= Testing Pacemaker Failover

Trigger a failover by stopping node2:

[source,bash,role=execute]
----
virtctl stop rhel-ha-node2 -n %STUDENT_NAMESPACE%
----

Watch the cluster status:
[source,bash,role=execute]
----
pcs status
----
```

### 2. Build Image
```bash
cd content/workshop
podman build -t quay.io/tosin2013/retail-edge-bookbag:v1.1 .
podman push quay.io/tosin2013/retail-edge-bookbag:v1.1
```

### 3. Update Deployment
```bash
# Update image tag in values.yaml
yq eval '.bookbag.image.tag = "v1.1"' -i helm/retail-edge-ha/values.yaml

# Commit and push
git commit -am "Update Bookbag content to v1.1"
git push

# ArgoCD auto-syncs, students see new content within 3 minutes
```

## Alternative Platforms Considered

### Instruqt
**Reason**: SaaS platform, not self-hosted. Requires external dependency and costs.

### Katacoda (Deprecated)
**Reason**: Service shut down in 2022.

### Strigo
**Reason**: Commercial platform, not open-source or self-hosted.

## Notes

- Bookbag is actively maintained by Red Hat GPTE (Global Partner Training and Enablement)
- Used in dozens of Red Hat workshops and partner training programs
- Future enhancement: Add quizzes and progress tracking
- Consider accessibility (WCAG 2.1 AA compliance for screen readers)

## Related ADRs

- **ADR-0001**: Helm-based App of Apps Pattern (explains Bookbag deployment via ArgoCD)
- **ADR-0005**: ArgoCD Sync Wave Strategy (Bookbag deployed in Sync Wave 3)

## References

- [OpenShift Homeroom Project](https://github.com/openshift-homeroom)
- [Bookbag Container Image](https://quay.io/repository/redhat-gpte/bookbag)
- [AsciiDoc Writers Guide](https://asciidoctor.org/docs/asciidoc-writers-guide/)
- [Field-Sourced Content Template](https://github.com/rhpds/field-sourced-content-template)

---

**Author**: Tosin Akinosho
**Date**: 2026-03-22
**Reviewers**: Field Engineering Team, Workshop Content Team
**Supersedes**: None
**Superseded By**: None
