#!/bin/bash
set -e

NAMESPACE="backend-store"
GRANT="allow-edge-front"
ROUTE_NAMESPACE="edge-front"

if ! kubectl get referencegrant "$GRANT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ ReferenceGrant '$GRANT' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get referencegrant "$GRANT" -n "$NAMESPACE" -o json)

FROM=$(echo "$SPEC" | jq --arg ns "$ROUTE_NAMESPACE" '[.spec.from // [] | .[]
    | select(.group == "gateway.networking.k8s.io" and .kind == "HTTPRoute" and .namespace == $ns)] | length')
if [[ "$FROM" == "0" ]]; then
    echo "❌ ReferenceGrant '$GRANT' must allow HTTPRoute resources from the namespace '$ROUTE_NAMESPACE'"
    exit 1
fi

TO=$(echo "$SPEC" | jq '[.spec.to // [] | .[]
    | select((.group // "") == "" and .kind == "Service")] | length')
if [[ "$TO" == "0" ]]; then
    echo "❌ ReferenceGrant '$GRANT' must allow references to Service resources (core API group)"
    exit 1
fi

echo "✅ ReferenceGrant '$GRANT' lets HTTPRoutes in '$ROUTE_NAMESPACE' reference Services in '$NAMESPACE'"
exit 0
