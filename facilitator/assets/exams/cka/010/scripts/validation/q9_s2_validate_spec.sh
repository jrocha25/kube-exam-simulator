#!/bin/bash
set -e

NAMESPACE="ds-fleet"
DS="node-collector"

JSON=$(kubectl get daemonset "$DS" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ DaemonSet '$DS' not found in namespace '$NAMESPACE'"
    exit 1
fi

TOLERATED=$(jq '[.spec.template.spec.tolerations[]? | select(.key=="node-role.kubernetes.io/control-plane" or (.key==null and .operator=="Exists"))] | length' <<<"$JSON")
if [[ "${TOLERATED:-0}" -lt 1 ]]; then
    echo "❌ The Pod template does not tolerate the node-role.kubernetes.io/control-plane taint"
    exit 1
fi

CNAME=$(jq -r '.spec.template.spec.containers[0].name' <<<"$JSON")
IMAGE=$(jq -r '.spec.template.spec.containers[0].image' <<<"$JSON")
COUNT=$(jq '.spec.template.spec.containers | length' <<<"$JSON")
if [[ "$COUNT" != "1" || "$CNAME" != "collector" || "$IMAGE" != "busybox:1.36" ]]; then
    echo "❌ Expected one container named 'collector' running busybox:1.36 (found $COUNT: '$CNAME' / '$IMAGE')"
    exit 1
fi

VOLUME=$(jq -r '.spec.template.spec.volumes[]? | select(.hostPath.path=="/var/log") | .name' <<<"$JSON" | head -1)
if [[ -z "$VOLUME" ]]; then
    echo "❌ No hostPath volume for /var/log"
    exit 1
fi
MOUNT=$(jq -r --arg v "$VOLUME" '.spec.template.spec.containers[0].volumeMounts[]? | select(.name==$v and .mountPath=="/host/log") | .readOnly // false' <<<"$JSON")
if [[ -z "$MOUNT" ]]; then
    echo "❌ The '$VOLUME' volume is not mounted at /host/log"
    exit 1
fi
if [[ "$MOUNT" != "true" ]]; then
    echo "❌ /host/log is mounted read-write, expected read-only"
    exit 1
fi

echo "✅ '$DS' tolerates the control plane and mounts /var/log read-only at /host/log"
exit 0
