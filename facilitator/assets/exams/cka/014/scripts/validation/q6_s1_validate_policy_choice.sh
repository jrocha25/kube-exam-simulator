#!/bin/bash
set -e

NAMESPACE="harbor-api"

if [[ -z "$(kubectl get networkpolicy api-ingress-2 -n "$NAMESPACE" -o name 2>/dev/null)" ]]; then
    echo "❌ The least permissive policy (api-ingress-2) is not applied in '$NAMESPACE'"
    exit 1
fi

for other in api-ingress-1 api-ingress-3 api-ingress-4; do
    if kubectl get networkpolicy "$other" -n "$NAMESPACE" >/dev/null 2>&1; then
        echo "❌ '$other' is also applied in '$NAMESPACE'; apply only the least permissive policy"
        exit 1
    fi
done

# Exactly two policies: the seeded default deny and the chosen one.
COUNT=$(kubectl get networkpolicy -n "$NAMESPACE" -o json | jq '.items | length')
if [[ "$COUNT" != "2" ]]; then
    echo "❌ '$NAMESPACE' has $COUNT NetworkPolicies; expected default-deny-ingress plus the chosen one"
    exit 1
fi

# Applied as written, not edited into something else.
LIVE=$(kubectl get networkpolicy api-ingress-2 -n "$NAMESPACE" -o json | jq -S '.spec')
FILE=$(kubectl create --dry-run=client -f /tmp/exam/q6/api-ingress-2.yaml -o json 2>/dev/null | jq -S '.spec' || true)
if [[ -n "$FILE" && "$LIVE" != "$FILE" ]]; then
    echo "❌ api-ingress-2 was changed from the file it came from"
    exit 1
fi

echo "✅ api-ingress-2 is the only policy applied besides the default deny"
exit 0
