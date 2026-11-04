#!/bin/bash
set -e

NAMESPACE="manifest-ops"
DEPLOYMENT="manifest-api"
LOG_DIR="/var/log/manifest"

SPEC=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json 2>/dev/null | jq -c '.spec.template.spec' || true)
if [[ -z "$SPEC" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' not found in '$NAMESPACE'"
    exit 1
fi

# The shipper has to be running before schema-migrate starts, so it has to come
# first: init containers start strictly in list order.
ORDER=$(echo "$SPEC" | jq -c '[.initContainers[]?.name]')
if [[ "$ORDER" != '["manifest-shipper","schema-migrate"]' ]]; then
    echo "❌ Init containers are $ORDER; expected manifest-shipper followed by schema-migrate"
    exit 1
fi

if ! echo "$SPEC" | jq -e '.initContainers[0].restartPolicy == "Always"
        and .initContainers[0].image == "busybox:1.36"
        and (.initContainers[1].restartPolicy // "") == ""' >/dev/null; then
    echo "❌ manifest-shipper must be a native sidecar (restartPolicy: Always) running busybox:1.36, and schema-migrate must stay a plain init container"
    exit 1
fi

if [[ "$(echo "$SPEC" | jq -c '[.containers[].name]')" != '["api"]' ]]; then
    echo "❌ The Pod template must still have exactly one regular container, api"
    exit 1
fi

# All three mount the same emptyDir at the log directory.
VOLUMES=$(echo "$SPEC" | jq -r --arg d "$LOG_DIR" '
    [(.initContainers + .containers)[] | ([.volumeMounts[]? | select(.mountPath == $d) | .name][0] // "none")] | unique | .[]')
if [[ "$(echo "$VOLUMES" | wc -l)" != "1" || "$VOLUMES" == "none" ]]; then
    echo "❌ manifest-shipper, schema-migrate and api must all mount one shared volume at $LOG_DIR"
    exit 1
fi
if ! echo "$SPEC" | jq -e --arg v "$VOLUMES" '.volumes[] | select(.name == $v) | has("emptyDir")' >/dev/null; then
    echo "❌ The shared volume '$VOLUMES' is not an emptyDir"
    exit 1
fi

echo "✅ manifest-shipper is a native sidecar ahead of schema-migrate, sharing one emptyDir with both"
exit 0
