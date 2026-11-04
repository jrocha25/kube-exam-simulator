#!/bin/bash
set -e

# Read from a live Pod rather than the Deployment spec: the point of the upgrade
# is that the new value reached the containers that are actually running.

NAMESPACE="ops-charts"
EXPECTED="active"

for _ in $(seq 1 12); do
    POD=$(kubectl get pods -n "$NAMESPACE" -l app=beacon \
        --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    [[ -n "$POD" ]] && break
    sleep 5
done
if [[ -z "$POD" ]]; then
    echo "❌ No running Pod of the beacon release found in namespace '$NAMESPACE'"
    exit 1
fi

VALUE=$(kubectl get pod "$POD" -n "$NAMESPACE" \
    -o jsonpath='{.spec.containers[0].env[?(@.name=="BEACON_MESSAGE")].value}' 2>/dev/null || true)
if [[ "$VALUE" != "$EXPECTED" ]]; then
    echo "❌ The running container carries BEACON_MESSAGE='${VALUE:-unset}', expected '${EXPECTED}'"
    exit 1
fi

echo "✅ The upgraded value reached the running containers"
exit 0
