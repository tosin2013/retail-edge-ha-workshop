#!/bin/bash
# Patch Showroom terminal deployments to inject student environment variables
# This script must be run after deploying Showroom instances

set -e

STUDENT_COUNT="${1:-5}"

echo "Patching Showroom terminal deployments for $STUDENT_COUNT students..."
echo

for ((i=1; i<=STUDENT_COUNT; i++)); do
  printf -v student_id "%02d" "$i"
  NAMESPACE="showroom-student-$student_id"

  echo "📝 Patching terminal in $NAMESPACE..."

  # Check if namespace exists
  if ! oc get namespace "$NAMESPACE" &>/dev/null; then
    echo "⚠️  Namespace $NAMESPACE does not exist, skipping"
    continue
  fi

  # Check if deployment exists
  if ! oc get deployment showroom-terminal -n "$NAMESPACE" &>/dev/null; then
    echo "⚠️  Deployment showroom-terminal not found in $NAMESPACE, skipping"
    continue
  fi

  # Check if ConfigMap exists
  if ! oc get configmap student-env -n "$NAMESPACE" &>/dev/null; then
    echo "⚠️  ConfigMap student-env not found in $NAMESPACE, skipping"
    continue
  fi

  # Apply patch to inject student-env ConfigMap
  if oc patch deployment showroom-terminal -n "$NAMESPACE" --type=json -p='[
    {
      "op": "add",
      "path": "/spec/template/spec/containers/0/envFrom",
      "value": [
        {
          "configMapRef": {
            "name": "student-env"
          }
        }
      ]
    }
  ]' &>/dev/null; then
    echo "✅ Student $student_id patched successfully"
  else
    # Patch might already be applied
    if oc get deployment showroom-terminal -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].envFrom[*].configMapRef.name}' | grep -q "student-env"; then
      echo "✅ Student $student_id already has environment variables (patch already applied)"
    else
      echo "❌ Failed to patch student $student_id"
    fi
  fi
done

echo
echo "🎉 Patch complete! Verify with:"
echo "   oc exec -n showroom-student-01 deployment/showroom-terminal -- env | grep STUDENT_"
