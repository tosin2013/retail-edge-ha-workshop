# ADR-0001: Helm-based App of Apps Pattern

## Status

**Accepted** - 2026-03-22

## Context and Problem Statement

The Retail Edge HA Workshop requires deploying complex, multi-component infrastructure for 11-50 concurrent students. Each student needs:
- Isolated namespaces with resource quotas
- User Defined Networks (UDNs) for Layer 2 VM connectivity
- VirtualMachines across 3 modules (9 VMs per student = 450 VMs at maximum scale)
- RBAC configuration for secure access
- Showroom workshop content delivery

**Key Requirements**:
1. **Declarative Configuration**: All settings managed via a single configuration file
2. **GitOps-Native**: Automated sync and reconciliation via ArgoCD
3. **Scalability**: Support 1-50 students with same codebase
4. **Component Management**: Enable/disable individual modules independently
5. **Multi-User Provisioning**: Systematic creation of per-student resources

**Question**: What deployment pattern should we use to manage this complex, multi-user workshop infrastructure?

## Decision Drivers

- **Complexity**: 7+ distinct component types (infrastructure, networking, VMs, RBAC, etc.)
- **Scale**: Variable student count (1-50) requires dynamic resource generation
- **GitOps Requirement**: Must integrate with OpenShift GitOps (ArgoCD)
- **Maintainability**: Single source of truth for all configuration
- **Agnosticd Integration**: Must align with field-sourced-content-template patterns

## Considered Options

### Option 1: Raw Kubernetes Manifests with Kustomize Overlays
**Pros**:
- Simple, no additional tooling beyond Kustomize
- Direct control over every manifest
- Familiar to Kubernetes administrators

**Cons**:
- Extensive duplication for multi-user provisioning (50+ files per student)
- No templating engine for dynamic values (student count, cluster domain)
- Difficult to enable/disable components
- Poor DRY (Don't Repeat Yourself) compliance

### Option 2: Ansible-Only Approach
**Pros**:
- Powerful for procedural automation
- Good Agnosticd integration (ocp4_workload role pattern)
- Can handle complex logic for multi-user provisioning

**Cons**:
- Imperative rather than declarative
- Requires Ansible Runner jobs in cluster
- Less GitOps-friendly (state managed by playbook runs, not Git)
- Harder to visualize resource dependencies

### Option 3: Helm with App of Apps Pattern (SELECTED)
**Pros**:
- **Declarative**: `values.yaml` as single source of truth
- **GitOps-Native**: ArgoCD watches Helm chart in Git
- **Scalable**: Template once, render for 1-50 students
- **Component Management**: Feature flags for modules (`.Values.virtualMachines.module1.enabled`)
- **Dependency Ordering**: Sync waves (0=infra, 1=network, 2=VMs, 3=apps)
- **Proven Pattern**: Used extensively in field-sourced-content-template examples

**Cons**:
- Requires Helm knowledge
- Template syntax complexity for nested loops
- Debugging template rendering issues

### Option 4: Hybrid Helm + Ansible
**Pros**:
- Combines declarative (Helm) and procedural (Ansible) strengths
- Good for complex provisioning logic

**Cons**:
- Increased complexity (two systems to maintain)
- Duplication of configuration between Helm values and Ansible vars
- Unclear boundary between Helm and Ansible responsibilities

## Decision

**We will use Helm with the App of Apps pattern**, deploying via ArgoCD.

### Implementation Details

**Architecture**:
```
Parent ArgoCD Application (helm/retail-edge-ha)
├── values.yaml (single source of truth)
├── Child App: Infrastructure (Sync Wave 0)
├── Child App: Networking (Sync Wave 1)
├── Child App: RBAC (Sync Wave 1)
├── Child App: VMs Module 1 (Sync Wave 2)
├── Child App: VMs Module 2 (Sync Wave 2)
├── Child App: VMs Module 3 (Sync Wave 2)
└── Child App: Showroom (Sync Wave 3)
```

**Configuration Example**:
```yaml
# values.yaml
students:
  count: 25
virtualMachines:
  module1:
    enabled: true
  module2:
    enabled: true
  module3:
    enabled: false  # Disable via feature flag
```

**Deployment**:
```bash
# Single ArgoCD Application creates entire workshop
oc apply -f argocd-parent-app.yaml
argocd app sync retail-edge-ha-workshop
```

## Consequences

### Positive

✅ **Single Configuration File**: `values.yaml` controls all aspects of deployment
✅ **GitOps-Native**: Changes committed to Git automatically sync via ArgoCD
✅ **Scalable**: Same chart deploys 1 student or 50 students
✅ **Component Isolation**: Each child app can be synced/updated independently
✅ **Dependency Management**: Sync waves ensure proper startup order
✅ **Disaster Recovery**: Git repository is source of truth, full environment recreatable
✅ **Version Control**: Helm chart versions track workshop iterations

### Negative

❌ **Learning Curve**: Team must understand Helm templating (Go templates)
❌ **Template Complexity**: Nested loops for student provisioning can be hard to debug
   - *Mitigation*: Use `helm template` for local rendering and validation
   - *Mitigation*: Comprehensive inline comments in templates

❌ **Helm Knowledge Required**: Operators need Helm CLI familiarity
   - *Mitigation*: Provide clear documentation and common command examples
   - *Mitigation*: ArgoCD UI provides visual feedback, reducing CLI dependency

❌ **Limited Procedural Logic**: Cannot easily express complex conditionals
   - *Mitigation*: Use Agnosticd role for advanced provisioning scenarios
   - *Mitigation*: Keep templates simple, move complexity to values.yaml

### Neutral

⚖️ **ArgoCD Dependency**: Requires OpenShift GitOps operator
   - This is acceptable as it's a standard OpenShift component

⚖️ **Sync Wave Ordering**: Sequential deployment waves slower than parallel
   - This is acceptable for correctness (VMs need namespaces first)

## Validation

**Success Criteria**:
1. `helm template` renders valid manifests for 5, 25, and 50 students
2. ArgoCD successfully syncs all 7 child applications
3. Changing `students.count` in values.yaml triggers automatic reconciliation
4. Disabling a module via feature flag removes those resources

**Testing**:
```bash
# Validate template rendering
helm template retail-edge-ha ./helm/retail-edge-ha --values values.yaml

# Verify child apps created
argocd app list | grep retail-edge

# Test student count change
yq eval '.students.count = 10' -i helm/retail-edge-ha/values.yaml
git commit -am "Scale to 10 students"
git push
# ArgoCD auto-syncs, creates 10 additional namespaces
```

## Alternatives Considered Details

### Why Not Kustomize?
Kustomize overlays would require:
- `base/` directory with template manifests
- `overlays/student-01/`, `overlays/student-02/`, ... `overlays/student-50/`
- 50 duplicate kustomization.yaml files

**Example**:
```
kustomize/
├── base/
│   ├── namespace.yaml
│   └── kustomization.yaml
└── overlays/
    ├── student-01/
    │   └── kustomization.yaml
    ├── student-02/
    │   └── kustomization.yaml
    ...
    └── student-50/
        └── kustomization.yaml
```

This violates DRY and makes student count changes painful.

### Why Not Pure Ansible?
Ansible approach would require:
```yaml
# playbook.yml
- name: Create student namespaces
  k8s:
    state: present
    definition: "{{ lookup('template', 'namespace.yaml.j2') }}"
  loop: "{{ range(1, num_students + 1) | list }}"
```

While this works, it's **imperative** (defines *how* to achieve state) rather than **declarative** (defines *desired state*). GitOps thrives on declarative configurations.

## Notes

- This decision aligns with the field-sourced-content-template `examples/helm` path
- Helm charts are versioned, enabling workshop iterations (v1.0, v1.1, v2.0)
- ArgoCD provides health checks and automatic rollback on failures
- Future enhancement: Multi-cluster deployment (regional rollout)

## Related ADRs

- **ADR-0002**: Multi-User Namespace Isolation (explains namespace strategy)
- **ADR-0005**: ArgoCD Sync Wave Strategy (explains dependency ordering)

## References

- [Helm Documentation](https://helm.sh/docs/)
- [ArgoCD App of Apps Pattern](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/)
- [Field-Sourced Content Template - Helm Examples](https://github.com/rhpds/field-sourced-content-template/tree/main/examples/helm)
- [GitOps Principles](https://opengitops.dev/)

---

**Author**: Tosin Akinosho
**Date**: 2026-03-22
**Reviewers**: Field Engineering Team
**Supersedes**: None
**Superseded By**: None
