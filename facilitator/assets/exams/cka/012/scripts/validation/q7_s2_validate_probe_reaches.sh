#!/bin/bash
set -e

# The traffic check, from the Pod the question names. Five attempts, not twelve:
# a five-second connect plus a five-second sleep, twelve times, is 120 seconds and
# the script cap is 90 -- and the slow path is the wrong answer.
#
# nginx is Debian-based, so the client has the bash whose /dev/tcp this uses; the
# image ships no curl and no wget.

NAMESPACE="svc-catalog"
SERVICE="station-catalog-svc"
CLIENT="catalog-probe"
PORT=80
ATTEMPTS=5

if ! kubectl get service "$SERVICE" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Service '$SERVICE' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o json)
TYPE=$(jq -r '.spec.type // ""' <<<"$JSON")
CLUSTER_IP=$(jq -r '.spec.clusterIP // ""' <<<"$JSON")
SVC_PORT=$(jq -r '[.spec.ports[].port] | map(tostring) | join(" ")' <<<"$JSON")

if [[ "$TYPE" != "ClusterIP" ]]; then
    echo "❌ '$SERVICE' is of type '${TYPE:-unset}', and it was to stay ClusterIP"
    exit 1
fi
if [[ " ${SVC_PORT} " != *" ${PORT} "* ]]; then
    echo "❌ '$SERVICE' listens on port(s) '${SVC_PORT:-none}', and it was to stay ${PORT}"
    exit 1
fi
if [[ -z "$CLUSTER_IP" || "$CLUSTER_IP" == "None" ]]; then
    echo "❌ '$SERVICE' has no cluster IP"
    exit 1
fi
if [[ "$(kubectl get pod "$CLIENT" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null)" != "Running" ]]; then
    echo "❌ Pod '$CLIENT' is not Running; it is part of the lab"
    exit 1
fi

REACHED=no
for _ in $(seq 1 $ATTEMPTS); do
    if kubectl exec -n "$NAMESPACE" "$CLIENT" -- timeout 4 bash -c "echo > /dev/tcp/${CLUSTER_IP}/${PORT}" >/dev/null 2>&1 </dev/null; then
        REACHED=yes
        break
    fi
    sleep 3
done

if [[ "$REACHED" != yes ]]; then
    echo "❌ '$CLIENT' cannot reach '$SERVICE' (${CLUSTER_IP}) on port ${PORT}"
    exit 1
fi

echo "✅ '$CLIENT' reaches '$SERVICE' on ${CLUSTER_IP}:${PORT}"
exit 0
