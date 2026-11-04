#!/bin/bash
set -e

NAMESPACE="quay-edge"

if [[ -z "$(kubectl get httproute quay-web -n "$NAMESPACE" -o name 2>/dev/null)" ]]; then
    echo "❌ The replacement HTTPRoute 'quay-web' does not exist"
    exit 1
fi

if kubectl get ingress quay-web -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ The Ingress 'quay-web' still exists"
    exit 1
fi

for svc in quay-web quay-status; do
    if ! kubectl get service "$svc" -n "$NAMESPACE" >/dev/null 2>&1; then
        echo "❌ The Service '$svc' was deleted along with the Ingress"
        exit 1
    fi
done

echo "✅ The Ingress is gone and both Services remain"
exit 0
