# ADR-0002: Multi-User Namespace Isolation Strategy

## Status

**Accepted** - 2026-03-22

## Context and Problem Statement

The Retail Edge HA Workshop must support 11-50 concurrent students, each deploying 9 VirtualMachines with isolated networking. We need to prevent:
- Resource conflicts (VM name collisions, IP address conflicts)
- Security breaches (Student A accessing Student B's VMs)
- Resource hoarding (one student consuming all cluster resources)
- Network leakage (VMs communicating across student boundaries)

**Question**: How should we isolate student environments to ensure security, resource fairness, and network separation?

## Decision Drivers

- **Security**: Students must not access each other's resources
- **Resource Fairness**: Prevent one student from starving others
- **Network Isolation**: Layer 2 UDNs must not leak between students
- **Operational Simplicity**: Easy cleanup after workshop
- **RBAC Alignment**: Leverage OpenShift's native RBAC model

## Considered Options

### Option 1: Single Shared Namespace
**Pros**:
- Simplest deployment (one namespace total)
- Easy RBAC (all students in one RoleBinding)

**Cons**:
- ❌ **No isolation**: Students can see/delete each other's VMs
- ❌ **Name collisions**: Two students can't create `rhel-ha-node1`
- ❌ **No quotas**: Cannot limit per-student resources
- ❌ **Network leakage**: UDNs apply namespace-wide

**Verdict**: Rejected - fundamentally insecure

### Option 2: Per-Student Workload Namespace Only
**Architecture**:
```
retail-edge-student-01  (VMs, services, etc.)
retail-edge-student-02
...
retail-edge-student-50
```

**Pros**:
- Clean separation of workloads
- Per-student resource quotas
- Simple RBAC (student-01 gets admin on retail-edge-student-01)

**Cons**:
- ⚠️ **UDN Limitation**: User Defined Networks require a namespace with specific labels
- ⚠️ **Network Attachment**: Cannot attach VMs to UDNs in different namespace

**Verdict**: Rejected - doesn't support UDN requirement

### Option 3: Dual Namespace Pattern (SELECTED)
**Architecture**:
```
retail-edge-student-01        # Workload namespace (VMs, services, etc.)
retail-edge-student-01-udn    # UDN namespace (network definitions)
retail-edge-student-02
retail-edge-student-02-udn
...
retail-edge-student-50
retail-edge-student-50-udn
```

**Pros**:
- ✅ **Full Isolation**: Each student has separate workload namespace
- ✅ **UDN Support**: Dedicated namespace with `k8s.ovn.org/primary-user-defined-network` label
- ✅ **Resource Quotas**: Applied to workload namespace
- ✅ **Network Isolation**: UDNs scoped to per-student UDN namespace
- ✅ **Clean Cleanup**: Delete 2 namespaces per student

**Cons**:
- Higher namespace count (100 for 50 students)
- Slightly more complex RBAC (2 namespaces per student)

**Verdict**: Selected - meets all requirements

### Option 4: Per-Module Namespaces
**Architecture**:
```
retail-edge-student-01-module1
retail-edge-student-01-module2
retail-edge-student-01-module3
```

**Pros**:
- Extreme isolation between modules
- Could disable module by deleting namespace

**Cons**:
- ❌ **Namespace Explosion**: 150 namespaces for 50 students (3 modules)
- ❌ **Operational Complexity**: Students manage 3 namespaces
- ❌ **Quota Fragmentation**: Hard to enforce total resource limits

**Verdict**: Rejected - over-engineered

## Decision

**We will use the Dual Namespace Pattern**: One workload namespace + one UDN namespace per student.

### Implementation

**Namespace Naming Convention**:
```
Workload:  retail-edge-student-{01..50}
UDN:       retail-edge-student-{01..50}-udn
```

**Namespace Labels**:
```yaml
# Workload Namespace
metadata:
  name: retail-edge-student-01
  labels:
    workshop: retail-edge-ha
    student-id: "01"
    argocd.argoproj.io/instance: retail-edge-ha

# UDN Namespace
metadata:
  name: retail-edge-student-01-udn
  labels:
    workshop: retail-edge-ha
    student-id: "01"
    k8s.ovn.org/primary-user-defined-network: ""  # Required for UDNs
```

**Resource Quota (per student)**:
```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: student-quota
  namespace: retail-edge-student-01
spec:
  hard:
    requests.cpu: "16"          # 9 VMs × 2 cores avg
    requests.memory: "32Gi"      # 9 VMs × 4GB avg
    persistentvolumeclaims: "10" # 1 per VM + spares
    requests.storage: "200Gi"    # 30+40+120 GB for VMs
    pods: "20"                   # VMs + virt-launcher pods
```

**RBAC**:
```yaml
# Student gets admin on their workload namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: student-01-admin
  namespace: retail-edge-student-01
subjects:
- kind: User
  name: student-01
roleRef:
  kind: ClusterRole
  name: admin

# Student gets view on their UDN namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: student-01-udn-view
  namespace: retail-edge-student-01-udn
subjects:
- kind: User
  name: student-01
roleRef:
  kind: ClusterRole
  name: view
```

## Consequences

### Positive

✅ **Security Isolation**: Students cannot access other students' resources
✅ **Network Isolation**: UDNs scoped to per-student namespace, no cross-talk
✅ **Resource Fairness**: Quotas prevent resource hogging
✅ **Clean Cleanup**: Delete 2 namespaces, all resources removed
✅ **RBAC Alignment**: Leverages OpenShift's native namespace-based security
✅ **Conflict Prevention**: Same VM names in different namespaces don't collide

### Negative

❌ **Namespace Count**: 100 namespaces for 50 students
   - *Mitigation*: Modern OpenShift clusters handle 1000+ namespaces easily
   - *Impact*: Minimal performance impact

❌ **RBAC Complexity**: 2 RoleBindings per student (workload + UDN)
   - *Mitigation*: Automated via Helm templates
   - *Impact*: Transparent to students

❌ **Quota Management**: Must set quotas on 50 namespaces
   - *Mitigation*: Helm template generates all quotas from values.yaml
   - *Impact*: One-time configuration

### Neutral

⚖️ **UDN Requirement**: User Defined Networks require dedicated namespace
   - This is a requirement of the OpenShift networking model, not a choice

⚖️ **Cleanup Coordination**: Must delete both namespaces per student
   - ArgoCD cascade delete handles this automatically

## Validation

**Test Cases**:

1. **Isolation Test**:
   ```bash
   # As student-01, try to access student-02's namespace
   oc project retail-edge-student-02
   # Expected: Error: You don't have permission to view namespace
   ```

2. **Quota Enforcement Test**:
   ```bash
   # Try to create 11th PVC (quota is 10)
   oc create -f large-pvc.yaml -n retail-edge-student-01
   # Expected: Error: exceeded quota
   ```

3. **Network Isolation Test**:
   ```bash
   # Start VMs in student-01 and student-02
   # VM in student-01 should NOT ping VM in student-02 UDN
   virtctl console rhel-ha-node1 -n retail-edge-student-01
   ping 10.101.2.5  # Student-02's VM IP
   # Expected: Network unreachable
   ```

4. **Cleanup Test**:
   ```bash
   # Delete student-01 namespaces
   oc delete namespace retail-edge-student-01 retail-edge-student-01-udn
   # Wait 2 minutes
   oc get all -n retail-edge-student-01
   # Expected: No resources found
   ```

## Namespace Lifecycle

### Creation (via Helm)
```yaml
{{- range $i := untilStep 1 (add1 .Values.students.count) 1 }}
---
apiVersion: v1
kind: Namespace
metadata:
  name: {{ $.Values.students.namespacePrefix }}-{{ $.Values.students.userbase }}-{{ printf "%02d" $i }}
  labels:
    workshop: {{ $.Values.global.workshopName }}
    student-id: {{ printf "%02d" $i }}
{{- end }}
```

### Deletion (via ArgoCD)
```bash
# Delete parent ArgoCD Application (cascades to all resources)
oc delete application retail-edge-ha-workshop -n openshift-gitops

# All 100 student namespaces deleted automatically
```

## Alternative Strategies Considered

### Cross-Namespace UDN Sharing
**Idea**: Use a single UDN namespace, create NetworkAttachmentDefinitions in each student namespace.

**Problem**: UDNs are namespace-scoped. Cross-namespace attachment is not supported in OVN-Kubernetes.

### Cluster-Level UDNs
**Idea**: Create cluster-scoped UDNs, use NetworkPolicies for isolation.

**Problem**: User Defined Networks are always namespace-scoped by design.

## Notes

- This pattern aligns with OpenShift's namespace-based multi-tenancy model
- Future enhancement: Automated namespace cleanup via CronJob after workshop ends
- Consider namespace resource budgets at cluster level (LimitRange for defaults)

## Related ADRs

- **ADR-0001**: Helm-based App of Apps Pattern (explains Helm template generation)
- **ADR-0003**: User Defined Networks for Layer 2 Connectivity (explains UDN requirements)

## References

- [OpenShift Multi-Tenancy Best Practices](https://docs.openshift.com/container-platform/latest/authentication/using-rbac.html)
- [Kubernetes Resource Quotas](https://kubernetes.io/docs/concepts/policy/resource-quotas/)
- [OVN-Kubernetes User Defined Networks](https://docs.openshift.com/container-platform/latest/networking/ovn_kubernetes_network_provider/about-ovn-kubernetes.html)

---

**Author**: Tosin Akinosho
**Date**: 2026-03-22
**Reviewers**: Field Engineering Team
**Supersedes**: None
**Superseded By**: None
