# ADR-0005: ArgoCD Sync Wave Strategy

## Status

**Accepted** - 2026-03-22

## Context and Problem Statement

The Retail Edge HA Workshop deploys complex, interdependent infrastructure with clear dependency chains:
- VirtualMachines require namespaces to exist first
- VMs require User Defined Networks (UDNs) before network attachment
- RBAC must be configured before students access resources
- Bookbag should deploy last (students shouldn't see guide before infrastructure is ready)

**Without ordering**, ArgoCD would sync all resources in parallel, causing failures:
- VM creation fails: "namespace retail-edge-student-01 not found"
- Network attachment fails: "UDN pacemaker-net does not exist"
- Bookbag shows instructions, but VMs aren't provisioned yet

**Question**: How should we order resource creation to ensure dependencies are satisfied?

## Decision Drivers

- **Dependency Chain**: 4 clear layers (infra → network → VMs → apps)
- **Failure Prevention**: Avoid race conditions and retry loops
- **Visibility**: Clear indication of deployment progress
- **Troubleshooting**: Easy to identify which layer failed
- **GitOps Native**: Must work within ArgoCD's declarative model

## Considered Options

### Option 1: Single Sync Wave (No Ordering)
**Approach**: Deploy all resources in parallel, rely on ArgoCD retries

**Pros**:
- Fastest deployment (everything in parallel)
- Simplest configuration (no annotations)

**Cons**:
- ❌ **Race Conditions**: VMs created before namespaces exist
- ❌ **Excessive Retries**: ArgoCD retries failed resources repeatedly
- ❌ **Poor UX**: Students see error states, confusing status
- ❌ **Logs Pollution**: Hundreds of retry errors in ArgoCD logs

**Verdict**: Rejected - unacceptable failure rate

### Option 2: Manual Sync with Dependencies
**Approach**: Disable auto-sync, operators manually sync in order

**Example**:
```bash
argocd app sync retail-edge-ha-infrastructure  # Wait
argocd app sync retail-edge-ha-networking      # Wait
argocd app sync retail-edge-ha-vms             # Wait
argocd app sync retail-edge-ha-bookbag         # Wait
```

**Pros**:
- Full control over timing
- Can pause between layers to verify

**Cons**:
- ❌ **Not GitOps**: Manual intervention required, not declarative
- ❌ **Not Scalable**: Operator must babysit every deployment
- ❌ **Error-Prone**: Easy to forget a step or sync in wrong order

**Verdict**: Rejected - defeats purpose of GitOps automation

### Option 3: Separate ArgoCD Projects with Dependencies
**Approach**: Use ArgoCD Projects with `syncWindows` and dependencies

**Cons**:
- ⚠️ **ArgoCD 2.5+ Required**: Sync windows are newer feature
- ⚠️ **Complex Configuration**: Hard to visualize dependencies
- ⚠️ **Not Standard**: Uncommon pattern in ArgoCD community

**Verdict**: Rejected - over-complicated

### Option 4: Sync Waves with Annotations (SELECTED)
**Approach**: Use `argocd.argoproj.io/sync-wave` annotations for ordering

**Example**:
```yaml
# Namespace (Wave 0)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"

# UDN (Wave 1)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1"

# VM (Wave 2)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "2"

# Bookbag (Wave 3)
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "3"
```

**Pros**:
- ✅ **Declarative**: Ordering defined in manifests, not manual steps
- ✅ **Visual**: ArgoCD UI shows sync wave progress
- ✅ **Standard**: Widely used ArgoCD pattern
- ✅ **Granular**: Can fine-tune order within a wave (0, 1, 2, ... 10, 11, ...)
- ✅ **Automatic**: ArgoCD handles ordering, no operator intervention

**Cons**:
- ⚠️ **Sequential Waves**: Each wave waits for previous, slower than parallel
   - *Mitigation*: Acceptable trade-off for correctness

**Verdict**: Selected - industry-standard pattern for ArgoCD

## Decision

**We will use ArgoCD Sync Waves** with the following ordering:

```
Wave -1: Parent ArgoCD Application (bootstraps everything)
Wave 0:  Infrastructure (Namespaces, ResourceQuotas, Operators)
Wave 1:  Networking (UDNs, NADs) & RBAC (Roles, Bindings)
Wave 2:  VirtualMachines (All modules)
Wave 3:  Bookbag (Workshop content delivery)
```

### Implementation

**Sync Wave Assignments**:

| Component | Wave | Rationale |
|-----------|------|-----------|
| **Parent ArgoCD Application** | -1 | Bootstraps all child apps |
| **Namespaces** | 0 | Must exist before any resources |
| **ResourceQuotas** | 0 | Applied to namespaces immediately |
| **OperatorGroups** | 0 | Required for operator installations |
| **User Defined Networks** | 1 | VMs need UDNs for network attachment |
| **NetworkAttachmentDefinitions** | 1 | Generated from UDNs |
| **ClusterRoles** | 1 | RBAC for student access |
| **RoleBindings** | 1 | Grant students namespace access |
| **ServiceAccounts** | 1 | For VM fencing agents |
| **VirtualMachines Module 1** | 2 | RHEL HA VMs |
| **VirtualMachines Module 2** | 2 | MicroShift VMs |
| **VirtualMachines Module 3** | 2 | Two-Node OpenShift VMs |
| **Bookbag Deployment** | 3 | Workshop guide (last) |
| **Bookbag Service/Route** | 3 | Expose workshop guide |

**Template Example** (Infrastructure):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-edge-ha-infrastructure
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/sync-wave: "0"  # Deploy first
spec:
  # ...
```

**Template Example** (VMs):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-edge-ha-vms-module1
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/sync-wave: "2"  # Deploy after networking
spec:
  # ...
```

**Template Example** (Bookbag):
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: retail-edge-ha-bookbag
  namespace: openshift-gitops
  annotations:
    argocd.argoproj.io/sync-wave: "3"  # Deploy last
spec:
  # ...
```

## Consequences

### Positive

✅ **Deterministic Ordering**: Resources always deploy in same sequence
✅ **Dependency Satisfaction**: Each wave completes before next begins
✅ **Failure Isolation**: If Wave 1 fails, Wave 2 doesn't start (no cascading failures)
✅ **Clear Progress**: ArgoCD UI shows "Wave 0: Synced, Wave 1: Syncing, Wave 2: Waiting"
✅ **Troubleshooting**: Easy to identify which layer failed ("stuck in Wave 1")
✅ **GitOps Native**: Fully declarative, no manual intervention

### Negative

❌ **Sequential Deployment**: Waves deploy one at a time, slower than parallel
   - Wave 0: ~30 seconds (namespaces/quotas)
   - Wave 1: ~60 seconds (UDNs/RBAC)
   - Wave 2: ~5 minutes (VMs provision, DataVolume import)
   - Wave 3: ~30 seconds (Bookbag)
   - **Total**: ~6.5 minutes (vs. ~5 minutes if fully parallel)
   - *Mitigation*: 1.5-minute overhead acceptable for reliability

❌ **Within-Wave Parallelism**: All resources in same wave deploy in parallel
   - If one resource in Wave 2 fails, entire wave retries
   - *Mitigation*: Use sub-waves if needed (2.1, 2.2, 2.3)

❌ **Health Check Dependency**: Wave N+1 waits for Wave N to be **Healthy**, not just **Synced**
   - If a VM is stuck in "Scheduling" (resource exhaustion), Wave 3 never starts
   - *Mitigation*: Set realistic resource quotas, monitor cluster capacity

### Neutral

⚖️ **Sync Wave is Per-Application**: Child apps are the unit of sync waves, not individual resources
   - This is why we have 7 child applications in the App of Apps pattern

⚖️ **Wave Numbers are Arbitrary**: Could use 0, 10, 20, 30 for more granularity
   - We chose 0, 1, 2, 3 for simplicity

## Validation

**Test Cases**:

1. **Order Verification Test**:
   ```bash
   # Deploy workshop
   oc apply -f argocd-parent-app.yaml

   # Watch sync progress
   watch argocd app list

   # Expected order:
   # 1. retail-edge-ha (parent) syncs first
   # 2. retail-edge-ha-infrastructure appears, syncs
   # 3. retail-edge-ha-networking appears, syncs
   # 4. retail-edge-ha-vms-* appears, syncs
   # 5. retail-edge-ha-bookbag appears, syncs
   ```

2. **Dependency Failure Test**:
   ```bash
   # Break Wave 1 (delete UDN CRD)
   oc delete crd userdefinednetworks.k8s.ovn.org

   # Sync workshop
   argocd app sync retail-edge-ha

   # Expected: Wave 1 fails, Wave 2 never starts (VMs not created)
   argocd app get retail-edge-ha-networking
   # Status: OutOfSync or Degraded

   argocd app get retail-edge-ha-vms-module1
   # Status: Waiting (not synced yet)
   ```

3. **Recovery Test**:
   ```bash
   # Fix Wave 1 (reinstall OVN-Kubernetes)
   oc apply -f ovn-kubernetes-operator.yaml

   # ArgoCD auto-heals
   # Expected: Wave 1 becomes Healthy, Wave 2 starts automatically
   ```

## Sync Wave Best Practices

### 1. Use Sparse Numbering
**Bad**: Wave 0, 1, 2, 3, 4, 5
**Good**: Wave 0, 10, 20, 30, 40

**Reason**: Allows inserting new waves later (e.g., 15 between 10 and 20)

### 2. Group Related Resources in Same Wave
**Example**: UDNs and RBAC both in Wave 1 (no dependency between them)

### 3. Sub-Waves for Fine-Grained Control
**Example**:
```yaml
# CRD first
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1.0"

# CR second
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "1.1"
```

### 4. Negative Waves for Prerequisites
**Example**: Wave -1 for parent app, -10 for namespace

### 5. Document Wave Rationale
**Example**: Add comment explaining why resource is in specific wave

## ArgoCD UI Visualization

**Sync Progress View**:
```
retail-edge-ha (Parent)
├── ✓ Wave -1: Synced (Healthy)
├── ✓ Wave 0: Synced (Healthy) - Infrastructure
│   ├── ✓ Namespaces (50)
│   └── ✓ ResourceQuotas (50)
├── ✓ Wave 1: Synced (Healthy) - Networking & RBAC
│   ├── ✓ UDNs (200)
│   └── ✓ RoleBindings (50)
├── ⟳ Wave 2: Syncing (Progressing) - VirtualMachines
│   ├── ✓ Module 1 VMs (100)
│   ├── ⟳ Module 2 VMs (60/100 ready)
│   └── ⏸ Module 3 VMs (waiting)
└── ⏸ Wave 3: Waiting - Bookbag
```

## Alternative Ordering Strategies Rejected

### Helm Pre/Post Hooks
**Reason**: Hooks are per-Helm-release, not per-resource. Doesn't give fine-grained control.

### Dependency Operator
**Reason**: Third-party operator, adds external dependency. Sync waves are native ArgoCD.

### Ordered Kustomize Bases
**Reason**: Kustomize doesn't have ordering concept, would need manual sync.

## Notes

- Sync waves are processed **per-application**, not globally across all ArgoCD apps
- Within a wave, resources sync in alphabetical order (undefined if not using sync-options)
- Health checks run after sync; wave progresses only when all resources healthy
- Future enhancement: Add `sync-options: SkipDryRunOnMissingResource=true` to avoid pre-flight failures

## Related ADRs

- **ADR-0001**: Helm-based App of Apps Pattern (explains child application structure)
- **ADR-0003**: User Defined Networks (explains why UDNs must be in Wave 1)

## References

- [ArgoCD Sync Waves Documentation](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/)
- [ArgoCD Resource Hooks and Waves](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/)
- [GitOps Principles - Declarative](https://opengitops.dev/)

---

**Author**: Tosin Akinosho
**Date**: 2026-03-22
**Reviewers**: Field Engineering Team, ArgoCD SMEs
**Supersedes**: None
**Superseded By**: None
