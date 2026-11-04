#!/bin/bash
set -e

NAMESPACE="wl-harbor"

ENFORCE=$(kubectl get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || true)
if [[ -z "$ENFORCE" ]]; then
    echo "❌ Namespace '$NAMESPACE' enforces no Pod Security level"
    exit 1
fi

# --dry-run=server runs the whole admission chain without creating anything.
OUT=$(kubectl run q6-root-probe -n "$NAMESPACE" --image=busybox:1.36 --restart=Never \
    --dry-run=server -- sleep 1 2>&1 || true)
if ! echo "$OUT" | grep -q 'violates PodSecurity'; then
    echo "❌ A Pod running as root is still admitted in '$NAMESPACE'"
    exit 1
fi

echo "✅ Pod Security admission rejects a root Pod in '$NAMESPACE'"
exit 0
