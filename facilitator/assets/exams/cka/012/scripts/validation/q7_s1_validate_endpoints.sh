#!/bin/bash
set -e

# Both faults have to be fixed for this to pass. EndpointSlice readiness comes
# from Pod readiness, so a corrected selector alone yields three ready addresses
# while the Service still forwards to a port nothing serves -- which is why the
# resolved port is asserted here too, rather than leaving the whole of the second
# fault to the traffic check.
#
# The expected addresses are the Deployment's Pod IPs, read live: they change on
# every warm-up.

NAMESPACE="svc-catalog"
SERVICE="station-catalog-svc"
SELECTOR="app=station-catalog,tier=api"
WANT=3
PORT=80

if ! kubectl get service "$SERVICE" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Service '$SERVICE' not found in namespace '$NAMESPACE'"
    exit 1
fi

POD_IPS=$(kubectl get pods -n "$NAMESPACE" -l "$SELECTOR" -o json 2>/dev/null \
    | jq -r '.items[] | select(.status.phase == "Running") | .status.podIP // empty' 2>/dev/null \
    | grep -v '^$' | sort || true)
IP_COUNT=$(printf '%s\n' "$POD_IPS" | grep -c . || true)
if [[ "${IP_COUNT:-0}" -ne "$WANT" ]]; then
    echo "❌ The lab's ${WANT} '$SELECTOR' Pods are not all Running (found ${IP_COUNT:-0}); nothing to judge yet"
    exit 1
fi

READY_IPS=""
for _ in $(seq 1 6); do
    READY_IPS=$(kubectl get endpointslice -n "$NAMESPACE" \
        -l "kubernetes.io/service-name=${SERVICE}" -o json 2>/dev/null \
        | jq -r '[.items[].endpoints[]? | select(.conditions.ready == true) | .addresses[0]] | .[]' 2>/dev/null \
        | grep -v '^$' | sort || true)
    COUNT=$(printf '%s\n' "$READY_IPS" | grep -c . || true)
    [[ "${COUNT:-0}" -eq "$WANT" ]] && break
    sleep 5
done

COUNT=$(printf '%s\n' "$READY_IPS" | grep -c . || true)
if [[ "${COUNT:-0}" -ne "$WANT" ]]; then
    echo "❌ '$SERVICE' has ${COUNT:-0} ready endpoint(s), expected ${WANT}"
    echo "   A Service finds its Pods by matching its selector against the Pods' labels,"
    echo "   not against the labels of the object that created them."
    exit 1
fi

if [[ "$READY_IPS" != "$POD_IPS" ]]; then
    echo "❌ '$SERVICE' has ${WANT} endpoints, but they are not the Pods of the Deployment"
    echo "   Endpoints: $(tr '\n' ' ' <<<"$READY_IPS")"
    echo "   Pod IPs:   $(tr '\n' ' ' <<<"$POD_IPS")"
    exit 1
fi

PORTS=$(kubectl get endpointslice -n "$NAMESPACE" -l "kubernetes.io/service-name=${SERVICE}" -o json 2>/dev/null \
    | jq -r '[.items[].ports[]?.port] | unique | .[]' 2>/dev/null | tr '\n' ' ' || true)
if [[ " ${PORTS} " != *" ${PORT} "* ]]; then
    echo "❌ '$SERVICE' forwards to port(s) '${PORTS:-none}', and the containers serve on ${PORT}"
    echo "   A targetPort naming a port the container never declares cannot be resolved."
    exit 1
fi

echo "✅ All ${WANT} Pods are ready endpoints of '$SERVICE', forwarding to container port ${PORT}"
exit 0
