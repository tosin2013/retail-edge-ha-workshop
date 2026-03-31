# AgnosticD Integration

This directory contains AgnosticD workload roles for deploying the Retail Edge HA Workshop via AgnosticD v2.

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

1. Clone AgnosticD v2:
   ```bash
   cd ~/Development
   git clone https://github.com/agnosticd/agnosticd-v2
   cd agnosticd-v2
   ./bin/agd setup
   ```

2. Copy the workload role:
   ```bash
   cp -r /path/to/retail-edge-ha-workshop/agnosticd-integration/ocp4_workload_retail_edge_ha \
     ~/Development/agnosticd-v2/roles/
   ```

3. Configure cluster access (create `~/Development/agnosticd-v2-vars/retail-edge-ha-vars.yml`):
   ```yaml
   num_users: 5
   ocp4_workload_retail_edge_ha_enable_module3: false
   ```

### Deployment

```bash
cd ~/Development/agnosticd-v2

# Deploy workshop
./bin/agd provision \
  --guid my-workshop \
  --config openshift-workloads \
  --account sandbox1234 \
  -e ocp4_workload=ocp4_workload_retail_edge_ha \
  -e @~/Development/agnosticd-v2-vars/retail-edge-ha-vars.yml

# Cleanup
./bin/agd destroy \
  --guid my-workshop \
  --config openshift-workloads \
  --account sandbox1234
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
