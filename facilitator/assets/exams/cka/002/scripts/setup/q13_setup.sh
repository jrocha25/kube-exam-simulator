#!/bin/bash
set -e

# Create namespace
kubectl create namespace gateway --dry-run=client -o yaml | kubectl apply -f -

# The cluster ships the standard-channel Gateway API CRDs with the bundled Traefik
# chart, and env-setup turns on Traefik's Gateway provider, so there is nothing to
# download here. The chart is applied asynchronously after the cluster comes up
# though, so wait for the CRDs to appear before waiting on their condition --
# "kubectl wait" errors out immediately on a resource that does not exist yet.
# Every wait here is bounded: a cluster whose image does not enable Traefik's
# kubernetesGateway provider has no Gateway API at all, and it has to say so in
# minutes rather than stall the warm-up for the whole exam.
for crd in gatewayclasses gateways httproutes; do
    for attempt in $(seq 1 24); do
        if kubectl get "crd/${crd}.gateway.networking.k8s.io" >/dev/null 2>&1; then
            break
        fi
        if [ $(( attempt % 6 )) -eq 0 ]; then
            echo "Waiting for CRD ${crd}.gateway.networking.k8s.io ($(( attempt * 5 ))s)..."
        fi
        sleep 5
    done
    kubectl wait --for=condition=established --timeout=60s "crd/${crd}.gateway.networking.k8s.io" || {
        echo "WARNING: the Gateway API is not available in this cluster."
        echo "WARNING: the cluster image in use does not enable Traefik's kubernetesGateway"
        echo "WARNING: provider, so the Gateway API CRDs were never installed."
        echo "WARNING: rebuild the cluster image with:  ./start.sh --rebuild"
        exit 0
    }
done

# Wait for the traefik GatewayClass to be accepted, otherwise a Gateway created by
# the candidate would never be programmed.
STATUS=""
for attempt in $(seq 1 24); do
    STATUS=$(kubectl get gatewayclass traefik -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)
    if [ "$STATUS" = "True" ]; then
        break
    fi
    sleep 5
done

if [ "$STATUS" != "True" ]; then
    echo "WARNING: GatewayClass traefik did not become Accepted in time"
else
    echo "GatewayClass traefik is accepted"
fi

echo "Setup completed for Question 13"
