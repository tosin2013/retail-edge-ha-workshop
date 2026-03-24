#!/bin/bash
# =============================================================================
# Retail Edge HA Workshop - Deployment Validation Script
# =============================================================================
# This script validates the Helm chart and deployment configuration.
#
# Usage:
#   ./scripts/validate-deployment.sh [student-count]
#
# Example:
#   ./scripts/validate-deployment.sh 5
# =============================================================================

set -e

STUDENT_COUNT=${1:-5}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
HELM_CHART="${REPO_ROOT}/helm/retail-edge-ha"

echo "=========================================="
echo "Retail Edge HA Workshop - Validation"
echo "=========================================="
echo ""

# Check Helm is installed
if ! command -v helm &> /dev/null; then
    echo "❌ ERROR: helm command not found"
    echo "   Please install Helm: https://helm.sh/docs/intro/install/"
    exit 1
fi

echo "✓ Helm is installed: $(helm version --short)"
echo ""

# Validate Helm chart syntax
echo "📋 Validating Helm chart syntax..."
if helm lint "${HELM_CHART}"; then
    echo "✓ Helm chart syntax is valid"
else
    echo "❌ ERROR: Helm chart syntax validation failed"
    exit 1
fi
echo ""

# Test template rendering
echo "🔧 Testing Helm template rendering for ${STUDENT_COUNT} students..."
TEMP_OUTPUT=$(mktemp -d)

if helm template retail-edge-ha "${HELM_CHART}" \
    --set students.count="${STUDENT_COUNT}" \
    --output-dir "${TEMP_OUTPUT}" > /dev/null 2>&1; then
    echo "✓ Helm templates rendered successfully"
else
    echo "❌ ERROR: Helm template rendering failed"
    rm -rf "${TEMP_OUTPUT}"
    exit 1
fi

# Count rendered resources
echo ""
echo "📊 Rendered Resources:"
echo "   Namespaces expected: $((STUDENT_COUNT * 2)) (2 per student)"
echo "   ResourceQuotas expected: ${STUDENT_COUNT}"
echo ""

# Validate namespace count
NAMESPACE_COUNT=$(grep -r "kind: Namespace" "${TEMP_OUTPUT}" | wc -l)
EXPECTED_NAMESPACES=$((STUDENT_COUNT * 2 + 2))  # Students + infrastructure + showroom

if [ "${NAMESPACE_COUNT}" -eq "${EXPECTED_NAMESPACES}" ]; then
    echo "✓ Namespace count correct: ${NAMESPACE_COUNT}"
else
    echo "⚠️  WARNING: Namespace count mismatch"
    echo "   Expected: ${EXPECTED_NAMESPACES}"
    echo "   Rendered: ${NAMESPACE_COUNT}"
fi

# Validate ArgoCD Applications
ARGOCD_APP_COUNT=$(grep -r "kind: Application" "${TEMP_OUTPUT}" | wc -l)
EXPECTED_APPS=5  # parent + infrastructure + networking + rbac + showroom

if [ "${ARGOCD_APP_COUNT}" -ge "${EXPECTED_APPS}" ]; then
    echo "✓ ArgoCD Applications found: ${ARGOCD_APP_COUNT}"
else
    echo "⚠️  WARNING: ArgoCD Application count low"
    echo "   Expected: at least ${EXPECTED_APPS}"
    echo "   Rendered: ${ARGOCD_APP_COUNT}"
fi

# Check sync wave annotations
echo ""
echo "🔄 Sync Wave Annotations:"
for wave in 0 1 2 3; do
    COUNT=$(grep -r "argocd.argoproj.io/sync-wave.*${wave}" "${TEMP_OUTPUT}" | wc -l)
    echo "   Wave ${wave}: ${COUNT} resources"
done

# Cleanup
rm -rf "${TEMP_OUTPUT}"

echo ""
echo "=========================================="
echo "✅ Validation Complete!"
echo "=========================================="
echo ""
echo "Next Steps:"
echo "  1. Review values.yaml configuration"
echo "  2. Commit changes to Git"
echo "  3. Deploy to OpenShift cluster"
echo ""
echo "Deploy Command:"
echo "  oc apply -f - <<EOF"
echo "  apiVersion: argoproj.io/v1alpha1"
echo "  kind: Application"
echo "  metadata:"
echo "    name: retail-edge-ha-workshop"
echo "    namespace: openshift-gitops"
echo "  spec:"
echo "    project: default"
echo "    source:"
echo "      repoURL: https://github.com/tosin2013/retail-edge-ha-workshop.git"
echo "      targetRevision: main"
echo "      path: helm/retail-edge-ha"
echo "    destination:"
echo "      server: https://kubernetes.default.svc"
echo "      namespace: retail-edge-infrastructure"
echo "  EOF"
echo ""
