# Contributing to Retail Edge HA Workshop

## Repository Structure

- **`/helm`** - Helm charts for workshop infrastructure
- **`/manifests`** - Kubernetes manifests (VMs, networking, UDNs)
- **`/content`** - Workshop content (Antora/AsciiDoc format for Showroom)
- **`/scripts`** - Automation and generation scripts
- **`/docs`** - Architecture Decision Records (ADRs) and guides

## Making Changes

### Infrastructure Changes
1. Update Helm charts or manifests
2. Run validation: `./scripts/validate-deployment.sh 5`
3. Test locally or in dev cluster
4. Update related documentation

### Content Changes
1. Edit AsciiDoc files in `/content/modules/ROOT/pages/`
2. Update navigation in `/content/modules/ROOT/nav.adoc` if adding modules
3. Commit and push changes - Showroom auto-deploys via GitOps
4. Verify content renders at Showroom route

### Configuration Sync
**CRITICAL**: Keep workshop configuration in sync:
- `/helm/retail-edge-ha/values.yaml` (primary configuration source)
- `/content/antora.yml` (Antora component configuration)
- `/content/site.yml` (Antora site configuration)

## Testing

1. **Helm validation**: `helm template ./helm/retail-edge-ha | oc apply --dry-run=client -f -`
2. **Content preview**: Access Showroom route and navigate through all modules
3. **End-to-end**: Deploy for 2-3 students and walk through all labs

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
