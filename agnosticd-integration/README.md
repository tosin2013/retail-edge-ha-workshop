# AgnosticD Integration

This directory contains AgnosticD workload roles for deploying the Retail Edge HA Workshop via AgnosticD v2.

## Prerequisites

Run this checklist before attempting any `agd provision` command.

| Requirement | Check command | Notes |
|-------------|---------------|-------|
| Python 3.12+ | `python3 --version` | Required by AgnosticD v2 |
| Podman | `podman --version` | Required to run the execution environment |
| AgnosticD v2 clone | `ls ~/Development/agnosticd-v2/bin/agd` | Clone from `tosin2013/agnosticd-v2` |
| `agd setup` done | `ls ~/Development/agnosticd-v2-virtualenv/` | Run `./bin/agd setup` once |
| **Pull secret** | `ls ~/pull-secret.yaml` | **Download from [console.redhat.com/openshift/install/pull-secret](https://console.redhat.com/openshift/install/pull-secret) and save as `~/pull-secret.yaml`** |
| AWS credentials | `aws sts get-caller-identity` | Must be in `~/.aws/credentials` (Open Environment) |
| Route53 hosted zone | `aws route53 list-hosted-zones` | Provided by RHDP Open Environment |
| Workload role in place | `ls ~/Development/agnosticd-v2/roles/ocp4_workload_retail_edge_ha/` | Copy from this repo |

### Pull Secret Quick Check

```bash
# Verify pull secret exists
ls -lh ~/pull-secret.yaml

# Inject into secrets.yml (run once after downloading)
PULL_SECRET=$(cat ~/pull-secret.yaml | tr -d '\n')
sed -i "s|'<REPLACE_WITH_PULL_SECRET>'|'${PULL_SECRET}'|g" \
  ~/Development/agnosticd-v2-secrets/secrets.yml
```

> The `cluster-deploy.sh` and `deploy.sh` scripts automatically detect `~/pull-secret.yaml`
> and inject it before running `agd provision`, so manual injection is only needed if you
> run `agd provision` directly.

## Available Workload Roles

### ocp4_workload_retail_edge_ha

Deploys the complete Retail Edge HA Workshop to an existing OpenShift 4.21+ cluster with OpenShift Virtualization.

**Features:**
- Multi-user support (1-50 students)
- Three HA architecture modules (Pacemaker, MicroShift VRRP, Two-Node OpenShift)
- Automated Showroom lab guide deployment
- GitOps-based deployment via ArgoCD
- Comprehensive lifecycle management (provision/destroy)

**Quick Start:**

```bash
./bin/agd provision \
  --guid workshop-test \
  --config openshift-workloads \
  --account sandbox1234 \
  -e ocp4_workload=ocp4_workload_retail_edge_ha \
  -e num_users=2
```

**Documentation:** See [ocp4_workload_retail_edge_ha/readme.adoc](ocp4_workload_retail_edge_ha/readme.adoc)

## Integration with AgnosticD v2

### Installation

1. **Download your pull secret** (one-time prerequisite):
   ```bash
   # Download from https://console.redhat.com/openshift/install/pull-secret
   # Save as ~/pull-secret.yaml (single-line JSON blob)
   ls ~/pull-secret.yaml   # verify it exists
   ```

2. Clone AgnosticD v2 (use the tosin2013 fork to track customizations):
   ```bash
   mkdir -p ~/Development
   cd ~/Development
   git clone https://github.com/tosin2013/agnosticd-v2
   cd agnosticd-v2
   ./bin/agd setup
   ```

3. Copy the workload role:
   ```bash
   # Target must be ansible/roles/ — NOT the top-level roles/ directory.
   # ansible.cfg sets: roles_path = ansible/dynamic_roles:ansible/roles
   cp -r /path/to/retail-edge-ha-workshop/agnosticd-integration/ocp4_workload_retail_edge_ha \
     ~/Development/agnosticd-v2/ansible/roles/
   ```
   If cloning from the `tosin2013/agnosticd-v2` fork, the role is already committed at
   `ansible/roles/ocp4_workload_retail_edge_ha/` and this step can be skipped.

4. Configure secrets (`~/Development/agnosticd-v2-secrets/secrets.yml`):
   ```bash
   # Inject the pull secret automatically from ~/pull-secret.yaml
   PULL_SECRET=$(cat ~/pull-secret.yaml | tr -d '\n')
   sed -i "s|'<REPLACE_WITH_PULL_SECRET>'|'${PULL_SECRET}'|g" \
     ~/Development/agnosticd-v2-secrets/secrets.yml
   # Then add your Red Hat activation key and org ID for RHEL VM subscription
   ```

5. Set cloud-specific secrets (`~/Development/agnosticd-v2-secrets/secrets-aws.yml`):
   ```yaml
   aws_access_key_id: "<from ~/.aws/credentials>"
   aws_secret_access_key: "<from ~/.aws/credentials>"
   base_domain: "<sandbox-id>.opentlc.com"   # from Route53 hosted zone
   agnosticd_aws_capacity_reservation_enable: false
   ```

6. Set vars files (`~/Development/agnosticd-v2-vars/`):
   - `openshift-cluster.yml` — cluster provisioning (OCP version, worker type, region)
   - `openshift-workloads.yml` — workshop workload (num_users, module flags)

### Deployment

A single script provisions the OCP cluster and deploys all workshop components end-to-end:

```bash
# Full deploy: OCP cluster + cert-manager + OpenShift Virtualization +
#              RHACM + student VMs + Showroom (~60-80 min total)
#    Requires: ~/pull-secret.yaml, AWS creds in ~/.aws/credentials
~/Development/agnosticd-v2-vars/retail-edge-ha/cluster-deploy.sh

# Tear down workload namespaces and resources (run before destroying cluster)
~/Development/agnosticd-v2-vars/retail-edge-ha/teardown.sh

# Tear down the OCP cluster and all AWS infrastructure
~/Development/agnosticd-v2-vars/retail-edge-ha/cluster-teardown.sh
```

If you need to re-deploy only the workshop workload after a content update or partial failure (without reprovisioning the cluster), use:

```bash
# Workload-only re-deploy — loads agnosticd-v2-vars/openshift-workloads.yml
~/Development/agnosticd-v2-vars/retail-edge-ha/deploy.sh
```

Or run `agd` directly:

```bash
cd ~/Development/agnosticd-v2

# Full provision (cluster + workshop) — single command
./bin/agd provision -g retail-ha -c openshift-cluster -a aws

# Workload-only re-deploy
./bin/agd provision -g retail-ha -c openshift-workloads -a aws

# Destroy workload resources
./bin/agd destroy -g retail-ha -c openshift-workloads -a aws

# Destroy cluster and all AWS resources
./bin/agd destroy -g retail-ha -c openshift-cluster -a aws
```

## Architecture

The AgnosticD role uses a **wrapper pattern** that:

1. Validates cluster prerequisites (OpenShift 4.21+, Virtualization operator, storage)
2. Clones the workshop repository
3. Templates Helm values from AgnosticD variables
4. Deploys the workshop Helm chart
5. Waits for ArgoCD to sync all resources
6. Returns Showroom URLs to students

This approach preserves the existing Helm + ArgoCD architecture while integrating with AgnosticD's lifecycle management.

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `num_users` | Number of students | `2` |
| `ocp4_workload_retail_edge_ha_enable_module1` | Enable Pacemaker module | `true` |
| `ocp4_workload_retail_edge_ha_enable_module2` | Enable MicroShift module | `true` |
| `ocp4_workload_retail_edge_ha_enable_module3` | Enable Two-Node OCP module | `true` |
| `ocp4_workload_retail_edge_ha_auto_start_vms` | Auto-start VMs | `false` |
| `ocp4_workload_retail_edge_ha_enable_showroom` | Deploy Showroom | `true` |
| `ocp4_workload_retail_edge_ha_auto_install_virtualization` | Auto-install OpenShift Virtualization operator if missing | `true` |
| `ocp4_workload_retail_edge_ha_rhel_activation_key` | Red Hat activation key for RHEL VM subscription | `""` (secrets) |
| `ocp4_workload_retail_edge_ha_rhel_org_id` | Red Hat organization ID for RHEL VM subscription | `""` (secrets) |

See [ocp4_workload_retail_edge_ha/readme.adoc](ocp4_workload_retail_edge_ha/readme.adoc) for complete variable reference.

## Resource Requirements

Per student (all modules enabled):
- **CPU**: 17 cores (2+2 for Module 1, 2+2 for Module 2, 4+4+1 for Module 3)
- **Memory**: 50 GiB (4+4 for Module 1, 4+4 for Module 2, 16+16+2 for Module 3)
- **Storage**: 200 GiB
- **VMs**: 7 (2 for Module 1, 2 for Module 2, 3 for Module 3)
- **Namespaces**: 2 (workload + UDN)

Default configuration (2 students): 34 CPU cores, 100 GiB RAM, 14 VMs
Maximum scale (50 students): ~850 CPU cores, 2.5 TiB RAM, 350 VMs

## Links

- [Workshop Repository](https://github.com/tosin2013/retail-edge-ha-workshop)
- [Workshop Documentation](https://tosin2013.github.io/retail-edge-ha-workshop/)
- [AgnosticD v2 Documentation](https://github.com/agnosticd/agnosticd-v2/blob/main/docs/setup.adoc)
- [Helm Chart](../helm/retail-edge-ha/)
