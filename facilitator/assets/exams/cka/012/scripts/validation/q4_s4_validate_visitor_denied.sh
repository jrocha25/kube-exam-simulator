#!/bin/bash
set -e

# The second flagged path. edge-visitor is in the approved namespace but carries
# no collector label, so the seeded policy's namespaceSelector entry lets it in on
# its own. Guarded on the approved path still working, for the same reason as s3.

NAMESPACE="net-array"
EDGE_NS="net-array-edge"
POLICY="array-ingress"
SERVER="station-relay"
ALLOWED="edge-collector"
CLIENT="edge-visitor"
PORT="8443"
ATTEMPTS=4

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicies are not enforced on this cluster, so this question cannot be graded."
    echo "   Rebuild with: ./start.sh --stop && ./start.sh --rebuild"
    exit 1
fi

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ NetworkPolicy '$POLICY' no longer exists in namespace '$NAMESPACE'"
    exit 1
fi

SERVER_IP=$(kubectl get pod "$SERVER" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null || true)
if [[ -z "$SERVER_IP" ]]; then
    echo "❌ Pod '$SERVER' in '$NAMESPACE' has no IP; it is part of the lab and should be Running"
    exit 1
fi

probe() {
    kubectl exec -n "$EDGE_NS" "$1" -- timeout 4 bash -c "echo > /dev/tcp/${SERVER_IP}/${PORT}" >/dev/null 2>&1 </dev/null
}

if ! probe "$ALLOWED"; then
    echo "❌ '$ALLOWED' cannot reach '$SERVER' on ${PORT} either, so the approved path is broken"
    echo "   Denying everything is not what the audit asked for."
    exit 1
fi

for _ in $(seq 1 $ATTEMPTS); do
    if probe "$CLIENT"; then
        echo "❌ '$CLIENT' in '$EDGE_NS' still reaches '$SERVER' on ${PORT}"
        echo "   Being in the approved namespace is not supposed to be enough on its own."
        exit 1
    fi
    sleep 3
done

echo "✅ '$CLIENT' is denied '$SERVER' on ${PORT} while '$ALLOWED' still gets through"
exit 0
