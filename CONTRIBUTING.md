# Contributing to Retail Edge HA Workshop

## Repository Structure

- **`/helm`** - Helm charts for workshop infrastructure
- **`/manifests`** - Kubernetes manifests (VMs, networking, UDNs)
- **`/bookbag`** - Workshop content and delivery (Bookbag/Homeroom)
- **`/scripts`** - Automation and generation scripts
- **`/docs`** - Architecture Decision Records (ADRs) and guides

## Making Changes

### Infrastructure Changes
1. Update Helm charts or manifests
2. Run validation: `./scripts/validate-deployment.sh 5`
3. Test locally or in dev cluster
4. Update related documentation

### Content Changes
1. Edit AsciiDoc files in `/bookbag/workshop/content/`
2. Preview locally (see bookbag/README.md)
3. Update `/bookbag/workshop/workshop.yaml` if variables change
4. Rebuild Bookbag image: `oc start-build retail-edge-ha-bookbag`

### Variable Sync
**CRITICAL**: Keep these in sync:
- `/bookbag/workshop/workshop.yaml` (content variables)
- `/helm/retail-edge-ha/values.yaml` (infrastructure config)
- `/bookbag/deploy/deployment.yaml` (runtime environment)

## Testing

1. **Helm validation**: `helm template ./helm/retail-edge-ha | oc apply --dry-run=client -f -`
2. **Content preview**: Deploy Bookbag locally and review all modules
3. **End-to-end**: Deploy for 1 student and walk through all labs

## Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):
- `feat: Add Module 5 for disaster recovery`
- `fix: Correct Pacemaker VIP configuration`
- `docs: Update Module 2 troubleshooting section`
- `chore: Regenerate VM manifests for 50 students`

## Pull Requests

1. Create feature branch: `git checkout -b feature/module-5`
2. Make changes and commit
3. Push and create PR against `main`
4. Ensure CI checks pass (when implemented)
5. Request review from @tosin2013
