#!/bin/bash
set -e

# Shared preamble. Setup scripts are picked up by the plain glob
# "q*_setup.sh" in jumphost/scripts/prepare-exam-env.sh, so this file runs first
# (glob order is q0, q1, q10..q18, q2..q9) even though no question maps to it.
#
# Its job is the one expensive check in this lab: whether the Gateway API is
# actually available. cka-004 folded that probe into its first Gateway question,
# which only worked because that question happened to sort first. Here the
# Gateway questions are q16-q18, which sort *after* most of the others, so the
# probe lives on its own and every Gateway question just reads the marker.
#
# The cluster ships the standard-channel Gateway API CRDs with the bundled Traefik
# chart, and kind-cluster/scripts/env-setup turns on Traefik's Gateway provider.
# The chart is applied asynchronously after the cluster comes up, so wait for the
# CRDs to appear before waiting on their condition -- "kubectl wait" errors out
# immediately on a resource that does not exist yet. Every wait is bounded: a
# cluster without the Gateway API has to say so in minutes rather than stall the
# whole warm-up.
GATEWAY_MARKER=/tmp/exam/gateway-api-unavailable

mkdir -p /tmp/exam
rm -f "$GATEWAY_MARKER"

GATEWAY_API_OK=yes
for crd in gatewayclasses gateways httproutes; do
    FOUND=no
    for attempt in $(seq 1 24); do
        if kubectl get "crd/${crd}.gateway.networking.k8s.io" >/dev/null 2>&1; then
            FOUND=yes
            break
        fi
        if [ $(( attempt % 6 )) -eq 0 ]; then
            echo "Waiting for CRD ${crd}.gateway.networking.k8s.io ($(( attempt * 5 ))s)..."
        fi
        sleep 5
    done

    if [ "$FOUND" != yes ]; then
        GATEWAY_API_OK=no
        continue
    fi

    kubectl wait --for=condition=established --timeout=60s "crd/${crd}.gateway.networking.k8s.io" \
        || GATEWAY_API_OK=no
done

# Wait for the traefik GatewayClass to be accepted, otherwise a Gateway created by
# the candidate would never be programmed.
if [ "$GATEWAY_API_OK" = yes ]; then
    STATUS=""
    for attempt in $(seq 1 24); do
        STATUS=$(kubectl get gatewayclass traefik -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)
        if [ "$STATUS" = "True" ]; then
            break
        fi
        if [ $(( attempt % 6 )) -eq 0 ]; then
            echo "Waiting for GatewayClass traefik to be accepted ($(( attempt * 5 ))s)..."
        fi
        sleep 5
    done

    if [ "$STATUS" != "True" ]; then
        GATEWAY_API_OK=no
        echo "WARNING: GatewayClass traefik did not become Accepted in time"
    fi
fi

# Leave the marker so q16-q18 skip their own wait, and say what to actually do
# about it rather than only naming the CRD that is missing.
if [ "$GATEWAY_API_OK" != yes ]; then
    echo "unavailable" > "$GATEWAY_MARKER"
    echo "WARNING: the Gateway API is not available in this cluster."
    echo "WARNING: the cluster image in use does not enable Traefik's kubernetesGateway"
    echo "WARNING: provider, so the Gateway API CRDs were never installed."
    echo "WARNING: rebuild the cluster image with:  ./start.sh --rebuild"
    echo "WARNING: questions 16-18 will not work until then."
fi

echo "Shared setup completed"
