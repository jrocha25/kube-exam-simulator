#!/bin/bash
set -e

NAMESPACE="ops-probe"
POD_LABEL="app=node-probe"
EXPECTED_PATH="/opt/probe-data"
EXPECTED_MOUNT="/etc/probe"

POD=$(kubectl get pods -n "$NAMESPACE" -l "$POD_LABEL" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$POD" ]]; then
    echo "❌ No Pod labelled '$POD_LABEL' found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json)

HOSTPATH=$(echo "$JSON" | jq -r '[.spec.volumes[] | select(.hostPath) | .hostPath.path] | first // empty')
if [[ "$HOSTPATH" != "$EXPECTED_PATH" ]]; then
    echo "❌ The Pod mounts host path '${HOSTPATH:-<none>}', expected '$EXPECTED_PATH'"
    exit 1
fi

VOLNAME=$(echo "$JSON" | jq -r '[.spec.volumes[] | select(.hostPath.path == "'"$EXPECTED_PATH"'") | .name] | first // empty')
MOUNTPATH=$(echo "$JSON" | jq -r '[.spec.containers[0].volumeMounts[] | select(.name == "'"$VOLNAME"'") | .mountPath] | first // empty')
if [[ "$MOUNTPATH" != "$EXPECTED_MOUNT" ]]; then
    echo "❌ Host path '$EXPECTED_PATH' is mounted at '${MOUNTPATH:-<nowhere>}', expected '$EXPECTED_MOUNT'"
    exit 1
fi

echo "✅ The Pod mounts '$EXPECTED_PATH' at '$EXPECTED_MOUNT'"
exit 0
