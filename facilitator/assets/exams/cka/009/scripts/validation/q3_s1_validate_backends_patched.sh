#!/bin/bash

set -e

NAMESPACE="kustom-patch"
ENV_NAME="SHIFT_WINDOW"
ENV_VALUE="night"

for DEPLOYMENT in route-planner dispatch-worker; do
    if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
        echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
        exit 1
    fi

    VALUE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json \
        | jq -r --arg n "$ENV_NAME" '
            [ .spec.template.spec.containers[]?.env[]? | select(.name == $n) | .value ][0] // ""')
    if [[ "$VALUE" != "$ENV_VALUE" ]]; then
        echo "❌ Deployment '$DEPLOYMENT' has ${ENV_NAME}='${VALUE:-unset}', expected '$ENV_VALUE'"
        exit 1
    fi
done

for _ in $(seq 1 12); do
    R1=$(kubectl get deployment route-planner -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2> /dev/null || true)
    R2=$(kubectl get deployment dispatch-worker -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2> /dev/null || true)
    [[ "$R1" == "1" && "$R2" == "1" ]] && break
    sleep 5
done

if [[ "$R1" != "1" || "$R2" != "1" ]]; then
    echo "❌ The backend Deployments are not both ready (route-planner=${R1:-0}, dispatch-worker=${R2:-0})"
    exit 1
fi

echo "✅ Both tier=backend Deployments carry ${ENV_NAME}=${ENV_VALUE} and are ready"
exit 0
