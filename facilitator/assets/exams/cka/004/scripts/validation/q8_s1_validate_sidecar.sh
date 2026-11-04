#!/bin/bash
set -e

NAMESPACE="logistics"
DEPLOYMENT="shipment-tracker"
SIDECAR="log-shipper"
IMAGE="busybox:1.36"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json \
    | jq --arg n "$SIDECAR" '[.spec.template.spec.initContainers // [] | .[] | select(.name == $n)] | first // empty')

if [[ -z "$SPEC" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' has no init container named '$SIDECAR'. A native sidecar is an initContainers entry"
    exit 1
fi

RESTART_POLICY=$(echo "$SPEC" | jq -r '.restartPolicy // empty')
if [[ "$RESTART_POLICY" != "Always" ]]; then
    echo "❌ '$SIDECAR' must set restartPolicy 'Always' to run as a native sidecar (got: '${RESTART_POLICY:-<none>}')"
    exit 1
fi

SIDECAR_IMAGE=$(echo "$SPEC" | jq -r '.image // empty')
if [[ "$SIDECAR_IMAGE" != "$IMAGE" ]]; then
    echo "❌ '$SIDECAR' must use the image '$IMAGE' (got: '${SIDECAR_IMAGE:-<none>}')"
    exit 1
fi

# command and args joined into one argv, so either way of splitting them is accepted.
# busybox resolves a bare `sh` to /bin/sh, so both spellings run the same shell.
ARGV=$(echo "$SPEC" | jq -c '[(.command // [])[], (.args // [])[]]')
COMMAND=$(echo "$ARGV" | jq -r 'join(" ")')
SHELL_BIN=$(echo "$ARGV" | jq -r '.[0] // empty')
FLAG=$(echo "$ARGV" | jq -r '.[1] // empty')
SCRIPT=$(echo "$ARGV" | jq -r '.[2] // empty')
if [[ "$SHELL_BIN" != "/bin/sh" && "$SHELL_BIN" != "sh" ]] || [[ "$FLAG" != "-c" ]] \
    || [[ "$SCRIPT" != *"tail -F /var/log/app/tracker.log"* ]]; then
    echo "❌ '$SIDECAR' must run '/bin/sh -c \"tail -F /var/log/app/tracker.log\"' (got: '$COMMAND')"
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT' runs '$SIDECAR' as a native sidecar"
exit 0
