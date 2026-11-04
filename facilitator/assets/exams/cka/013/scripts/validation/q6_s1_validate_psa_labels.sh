#!/bin/bash
set -e

NAMESPACE="wl-harbor"

ENFORCE=$(kubectl get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce}' 2>/dev/null || true)
VERSION=$(kubectl get namespace "$NAMESPACE" -o jsonpath='{.metadata.labels.pod-security\.kubernetes\.io/enforce-version}' 2>/dev/null || true)

if [[ "$ENFORCE" != "restricted" ]]; then
    echo "❌ Namespace '$NAMESPACE' does not enforce the restricted level (enforce='${ENFORCE}')"
    exit 1
fi
if [[ "$VERSION" != "v1.34" ]]; then
    echo "❌ The enforced level is pinned to '${VERSION:-latest}', expected v1.34"
    exit 1
fi

echo "✅ '$NAMESPACE' enforces restricted, pinned to v1.34"
exit 0
