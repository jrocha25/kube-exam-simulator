#!/bin/bash
set -e

NAMESPACE="ts-decom"

# The namespace controller retries with a backoff, so a namespace whose last
# finalizer was removed a moment ago may take a little while to go.
for _ in $(seq 1 12); do
    kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || break
    sleep 5
done
if kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Namespace '$NAMESPACE' still exists ($(kubectl get namespace "$NAMESPACE" -o jsonpath='{.status.phase}'))"
    exit 1
fi

# Force-finalizing a namespace deletes the Namespace object and nothing else:
# its resources stay in etcd and are still listed under the old name.
LEFT=$(kubectl get tidegauges.ops.ck-x.io -n "$NAMESPACE" -o name 2>/dev/null) || {
    echo "❌ The tidegauges resource type cannot be listed any more"
    exit 1
}
if [[ -n "$LEFT" ]]; then
    echo "❌ '$NAMESPACE' is gone but its resources were left behind: $(echo $LEFT)"
    exit 1
fi
LEFT=$(kubectl get configmaps -n "$NAMESPACE" -o name 2>/dev/null || true)
if [[ -n "$LEFT" ]]; then
    echo "❌ '$NAMESPACE' is gone but its resources were left behind: $(echo $LEFT)"
    exit 1
fi

echo "✅ '$NAMESPACE' is gone and nothing of it was left behind"
exit 0
