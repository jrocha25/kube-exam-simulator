#!/bin/bash
set -e

NAMESPACE="edge-team"
ROUTE="team-route"

if ! kubectl get httproute "$ROUTE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ HTTPRoute '$ROUTE' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get httproute "$ROUTE" -n "$NAMESPACE" -o json)

PARENT=$(echo "$SPEC" | jq -r '[.spec.parentRefs[]? | select(.name=="platform-gw" and .namespace=="edge-platform" and .sectionName=="web")] | length')
if [[ "$PARENT" == "0" ]]; then
    echo "❌ '$ROUTE' does not reference the 'web' listener of 'edge-platform/platform-gw'"
    exit 1
fi

HOSTNAME=$(echo "$SPEC" | jq -r '[.spec.hostnames[]? | select(. == "team.helioscale.io")] | length')
if [[ "$HOSTNAME" == "0" ]]; then
    echo "❌ '$ROUTE' does not serve the hostname 'team.helioscale.io'"
    exit 1
fi

BACKEND=$(echo "$SPEC" | jq -r '[.spec.rules[]? | .backendRefs[]? | select(.name=="team-api" and .port==80)] | length')
if [[ "$BACKEND" == "0" ]]; then
    echo "❌ '$ROUTE' does not route to the Service 'team-api' on port 80"
    exit 1
fi

echo "✅ '$ROUTE' targets the 'web' listener of 'edge-platform/platform-gw' for 'team.helioscale.io'"
exit 0
