# Retail Edge HA Workshop - RHDP Validation Integration

## Overview

The Retail Edge HA Workshop now includes comprehensive validation capabilities integrated with Red Hat Demo Platform (RHDP) using the **Field-Sourced Content pattern** recommended by the RHPDS engineering team.

## What's Been Implemented

### ✅ Enhanced Validation Script

**File**: `scripts/validate-workshop-deployment.sh`

**New Features:**

1. **RHACM Fleet Management Validation**
   - Validates RHACM operator installation
   - Checks MultiClusterHub status
   - Verifies ManagedCluster CRs for each student
   - Confirms cluster availability

2. **JSON Output Mode**
   - Machine-readable validation results
   - Structured data for programmatic consumption
   - Compatible with RHDP catalog integration

3. **CLI Argument Parsing**
   - `--students NUM` - Set expected student count
   - `--format FORMAT` - Choose output format (text, json, both)
   - `--output FILE` - Specify JSON output file path
   - `--help` - Display usage information

**Usage Examples:**

```bash
# Display help
./scripts/validate-workshop-deployment.sh --help

# Validate for 10 students (text output)
./scripts/validate-workshop-deployment.sh 10

# JSON output for 25 students
./scripts/validate-workshop-deployment.sh --students 25 --format json

# Both text and JSON output
./scripts/validate-workshop-deployment.sh -s 5 -f both -o report.json
```

### ✅ Kubernetes Validation Job (Field-Sourced Pattern)

**File**: `helm/retail-edge-ha/templates/validation-job.yaml`

**Features:**

- Runs as ArgoCD **PostSync hook** (automatic post-deployment)
- Clones workshop repository and executes validation script
- Creates ConfigMap with `demo.redhat.com/userinfo` label
- RHDP automatically displays validation results in catalog
- Minimal RBAC (read-only cluster access + ConfigMap create)

**Configuration** (`helm/retail-edge-ha/values.yaml`):

```yaml
validation:
  # Enable post-deployment validation job
  enabled: false  # Set to true to enable

  # Container image with oc CLI, git, and jq
  image: "registry.redhat.io/openshift4/ose-cli:latest"

  # Git repository containing validation scripts
  gitRepo: "https://github.com/tosin2013/retail-edge-ha-workshop.git"

  # Git branch or tag to use
  gitRef: "main"
```

## Field-Sourced Content Pattern

This implementation follows the RHPDS-recommended **Field-Sourced Content** pattern:

### Traditional Approach (NOT Used)
- ❌ Fork `agnosticd/core_workloads`
- ❌ Fork `redhat-cop/agnosticv`
- ❌ Create separate validation role
- ❌ Submit PRs to upstream repositories

### Field-Sourced Pattern (✅ What We Built)
- ✅ All logic in workshop repository
- ✅ RHDP points directly to workshop GitHub repo
- ✅ ArgoCD deploys content via GitOps
- ✅ ConfigMap with `demo.redhat.com/userinfo` label for catalog display
- ✅ No upstream dependencies

**Benefits:**
- Faster iteration (no PR approval delays)
- Single source of truth (workshop repo)
- Developer ownership and control
- Simpler architecture

## Validation Components

### What Gets Validated

The validation script checks:

1. **Prerequisites**
   - oc CLI installed
   - Cluster access
   - OpenShift version >= 4.21
   - OpenShift Virtualization operator
   - Storage class availability

2. **Helm Release**
   - Workshop Helm release deployed
   - Correct namespace and revision

3. **ArgoCD Applications**
   - Parent application synced
   - Child applications healthy
   - Expected number of apps deployed

4. **Namespaces**
   - Student workload namespaces (`retail-edge-student-{01..N}`)
   - Student UDN namespaces (`retail-edge-student-{01..N}-udn`)
   - Showroom namespaces (`showroom-student-{01..N}`)
   - Resource quotas applied

5. **Networking**
   - User Defined Networks (UDNs) created
   - Correct network configurations per module

6. **VirtualMachines**
   - Module 1: RHEL HA VMs (2 per student)
   - Module 2: MicroShift VMs (2 per student, optional)
   - Module 3: Two-Node OCP VMs (3 per student, optional)
   - DataVolume provisioning status

7. **Showroom Lab Guides**
   - Showroom pods running and ready
   - Routes accessible
   - ConfigMaps created
   - Environment variables patched

8. **Fleet Management (Optional)**
   - RHACM operator installed
   - MultiClusterHub running
   - ManagedCluster CRs created
   - Cluster availability status

### Validation Status Levels

- **HEALTHY** - All components running and accessible
- **DEGRADED** - Some components have partial issues (warnings)
- **FAILED** - Critical components missing or not running

## RHDP Integration

### ConfigMap Structure

The validation Job creates a ConfigMap that RHDP automatically picks up:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: workshop-validation-results
  namespace: retail-edge-infrastructure
  labels:
    demo.redhat.com/userinfo: ""  # RHDP integration label
data:
  validation_status: "HEALTHY"
  validation_timestamp: "2026-03-30T19:45:37Z"
  validation_total_checks: "15"
  validation_passed: "13"
  validation_warnings: "2"
  validation_failed: "0"
  validation_status_message: "Workshop is ready for students"
  validation_argocd_apps: "10"
  validation_argocd_synced: "10"
  validation_student_namespaces: "5"
  validation_showroom_namespaces: "5"
  validation_vms_total: "10"
  validation_datavolumes_ready: "10"
  validation_showroom_sample_url: "https://showroom-student-01.apps.cluster.example.com"
  workshop_name: "retail-edge-ha"
  workshop_students: "5"
```

### RHDP Catalog Display

When users order the workshop from RHDP catalog, they will see:

- ✅ Validation status badge (HEALTHY/DEGRADED/FAILED)
- 📊 Component health summary
- 🔗 Sample Showroom URL for testing
- 📈 Resource counts and readiness

## How to Enable Validation

### For Local Testing

1. **Deploy workshop** (if not already deployed):
   ```bash
   helm install retail-edge-ha ./helm/retail-edge-ha \
     --namespace retail-edge-ha-gitops \
     --create-namespace \
     --set students.count=2 \
     --set global.clusterDomain=$(oc get ingresses.config.openshift.io cluster -o jsonpath='{.spec.domain}') \
     --set global.clusterApiUrl=$(oc whoami --show-server)
   ```

2. **Run validation manually**:
   ```bash
   cd /home/vpcuser/retail-edge-ha-workshop
   ./scripts/validate-workshop-deployment.sh --students 2
   ```

3. **Test JSON output**:
   ```bash
   ./scripts/validate-workshop-deployment.sh --students 2 --format json
   jq '.' /tmp/validation-report.json
   ```

### For RHDP Deployment

1. **Enable validation in values.yaml**:
   ```yaml
   validation:
     enabled: true
     gitRepo: "https://github.com/tosin2013/retail-edge-ha-workshop.git"
     gitRef: "main"
   ```

2. **Commit and push** to your workshop repository

3. **RHDP will**:
   - Deploy workshop via ArgoCD
   - Run validation Job as PostSync hook
   - Display validation results in catalog

## Testing

### Test Validation Script

```bash
# Help
./scripts/validate-workshop-deployment.sh --help

# Text output (default)
./scripts/validate-workshop-deployment.sh 5

# JSON output
./scripts/validate-workshop-deployment.sh --students 10 --format json

# Both formats
./scripts/validate-workshop-deployment.sh -s 5 -f both -o /tmp/report.json

# Verify JSON
jq '.validation_status, .summary, .components' /tmp/report.json
```

### Test Helm Template

```bash
# Enable validation in test values
cat > /tmp/test-values.yaml <<EOF
validation:
  enabled: true
  gitRepo: "https://github.com/tosin2013/retail-edge-ha-workshop.git"
  gitRef: "main"
students:
  count: 5
EOF

# Render template
helm template retail-edge-ha ./helm/retail-edge-ha \
  --values /tmp/test-values.yaml \
  --show-only templates/validation-job.yaml

# Lint chart
helm lint ./helm/retail-edge-ha
```

## File Changes Summary

### Modified Files
- ✅ `scripts/validate-workshop-deployment.sh` - Enhanced with fleet validation, JSON output, CLI args
- ✅ `helm/retail-edge-ha/values.yaml` - Added validation configuration section

### New Files
- ✅ `helm/retail-edge-ha/templates/validation-job.yaml` - Kubernetes Job for automated validation
- ✅ `VALIDATION-INTEGRATION.md` - This documentation file

## Next Steps

### Before Deploying to RHDP

1. **Test locally**:
   - Deploy workshop with `validation.enabled=false`
   - Run validation script manually
   - Verify all checks pass

2. **Test with Job**:
   - Enable `validation.enabled=true`
   - Deploy/upgrade workshop
   - Check Job logs: `oc logs -n retail-edge-infrastructure -l app=retail-edge-ha-validation`
   - Verify ConfigMap created: `oc get configmap workshop-validation-results -n retail-edge-infrastructure`

3. **Review validation results**:
   ```bash
   oc get configmap workshop-validation-results -n retail-edge-infrastructure -o yaml
   ```

### For RHDP Submission

When ready to submit to RHDP:

1. Ensure `validation.enabled=true` in production values
2. Push final changes to GitHub repository
3. Submit workshop URL to RHDP catalog
4. RHDP will deploy using Field Content CI pattern
5. Validation runs automatically as PostSync hook

## Troubleshooting

### Validation Job Fails

```bash
# Check Job status
oc get jobs -n retail-edge-infrastructure

# Check Job logs
oc logs -n retail-edge-infrastructure -l app=retail-edge-ha-validation

# Check for RBAC issues
oc describe clusterrolebinding retail-edge-ha-validation
```

### ConfigMap Not Created

```bash
# Verify Job completed successfully
oc get jobs -n retail-edge-infrastructure

# Check if ConfigMap exists
oc get configmap -n retail-edge-infrastructure -l demo.redhat.com/userinfo

# Manually create ConfigMap (testing)
oc create configmap workshop-validation-results \
  --from-literal=validation_status=HEALTHY \
  -n retail-edge-infrastructure
oc label configmap workshop-validation-results demo.redhat.com/userinfo=""
```

### Validation Script Errors

```bash
# Run with debugging
bash -x ./scripts/validate-workshop-deployment.sh --students 5 --format json

# Check cluster access
oc whoami
oc version

# Verify namespaces exist
oc get namespaces | grep retail-edge
```

## References

- **Workshop Repository**: https://github.com/tosin2013/retail-edge-ha-workshop
- **Field-Sourced Content Template**: https://github.com/rhpds/field-sourced-content-template
- **RHDP Documentation**: (internal RHDP docs)
- **Validation Script**: `/scripts/validate-workshop-deployment.sh`
- **Plan File**: `/.claude/plans/generic-giggling-stardust.md`

## Support

For issues or questions:
- Review this documentation
- Check validation script logs
- Examine ArgoCD application status
- Review OpenShift Events in workshop namespaces
