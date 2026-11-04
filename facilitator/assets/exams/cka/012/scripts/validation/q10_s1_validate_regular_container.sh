#!/bin/bash
set -e

# The inverse of question 9's count. A native sidecar is not a regular container,
# so a Pod that runs an application plus a sidecar has exactly one entry under
# spec.containers. A candidate who adds the shipper as a second regular container
# gets the same two processes and the wrong object.

NAMESPACE="wl-shipper"
POD="trace-shipper"
WANT="trace-app"

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

COUNT=$(jq '(.spec.containers // []) | length' <<<"$JSON")
GOT=$(jq -r '[(.spec.containers // [])[].name] | join(",")' <<<"$JSON")

if [[ "$COUNT" != "1" || "$GOT" != "$WANT" ]]; then
    echo "❌ '$POD' must have exactly one regular container named '${WANT}' (found ${COUNT}: '${GOT:-none}')"
    echo "   A native sidecar belongs under initContainers, not alongside the application."
    exit 1
fi

echo "✅ '$POD' has exactly one regular container, '${WANT}'"
exit 0
