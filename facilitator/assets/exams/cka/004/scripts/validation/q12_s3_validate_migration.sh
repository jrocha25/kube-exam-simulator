#!/bin/bash
set -e

NAMESPACE="edge-migrate"
ROUTE="web-route"
INGRESS="legacy-web"

if kubectl get ingress "$INGRESS" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ The Ingress '$INGRESS' still exists; the migration is not finished"
    exit 1
fi

for SERVICE in catalog-svc profile-svc; do
    if ! kubectl get service "$SERVICE" -n "$NAMESPACE" &> /dev/null; then
        echo "❌ Service '$SERVICE' is missing; the backend Services must not be removed"
        exit 1
    fi
    PORT=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.ports[0].port}')
    if [[ "$PORT" != "80" ]]; then
        echo "❌ Service '$SERVICE' must keep port 80 (got: '$PORT')"
        exit 1
    fi
done

ACCEPTED=""
for _ in $(seq 1 12); do
    ACCEPTED=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json 2>/dev/null \
        | jq -r '[.status.parents[]? | .conditions[]? | select(.type == "Accepted" and .status == "True")] | length' || true)
    if [[ -n "$ACCEPTED" ]] && [[ "$ACCEPTED" != "0" ]]; then
        break
    fi
    sleep 5
done

if [[ -z "$ACCEPTED" ]] || [[ "$ACCEPTED" == "0" ]]; then
    echo "❌ HTTPRoute '$ROUTE' was not accepted by the Gateway"
    exit 1
fi

echo "✅ The legacy Ingress is gone and '$ROUTE' serves the traffic instead"
exit 0
