#!/bin/bash
set -e

NAMESPACE="harbor-api"

if [[ -z "$(kubectl get networkpolicy api-ingress-2 -n "$NAMESPACE" -o name 2>/dev/null)" ]]; then
    echo "❌ The chosen policy is not applied, so there is nothing to keep the default deny alongside"
    exit 1
fi

SPEC=$(kubectl get networkpolicy default-deny-ingress -n "$NAMESPACE" -o json 2>/dev/null | jq -c '.spec' || true)
if [[ "$SPEC" != '{"podSelector":{},"policyTypes":["Ingress"]}' ]]; then
    echo "❌ default-deny-ingress was removed or changed: ${SPEC:-missing}"
    exit 1
fi

echo "✅ default-deny-ingress is untouched"
exit 0
