#!/bin/bash
set -e

# Kustomize keeps no state, so taking a resource out of the configuration never
# removes the copy already in the cluster. This is the half of the question that
# a re-apply alone does not satisfy.

CONFIGMAP="refresh-config"

for ns in kustom-flight-staging kustom-flight-prod; do
    if kubectl get configmap "$CONFIGMAP" -n "$ns" >/dev/null 2>&1; then
        echo "❌ ConfigMap '$CONFIGMAP' still exists in namespace '$ns'"
        echo "   Removing it from the Kustomize configuration does not delete the copy in the cluster."
        exit 1
    fi
done

echo "✅ '$CONFIGMAP' is gone from both namespaces"
exit 0
