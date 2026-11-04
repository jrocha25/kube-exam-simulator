#!/bin/bash
set -e

# The first of the two paths the audit flagged. local-collector carries the
# collector label but runs in the server's own namespace, so the seeded policy's
# second "from" entry -- a bare podSelector, which is evaluated against the
# policy's own namespace -- lets it in.
#
# Guarded on the approved path still working, so that a deny-all scores nothing
# here. These five marks are the heart of the question.

NAMESPACE="net-array"
EDGE_NS="net-array-edge"
POLICY="array-ingress"
SERVER="station-relay"
ALLOWED="edge-collector"
CLIENT="local-collector"
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
    kubectl exec -n "$1" "$2" -- timeout 4 bash -c "echo > /dev/tcp/${SERVER_IP}/${PORT}" >/dev/null 2>&1 </dev/null
}

if ! probe "$EDGE_NS" "$ALLOWED"; then
    echo "❌ '$ALLOWED' cannot reach '$SERVER' on ${PORT} either, so the approved path is broken"
    echo "   Denying everything is not what the audit asked for."
    exit 1
fi

for _ in $(seq 1 $ATTEMPTS); do
    if probe "$NAMESPACE" "$CLIENT"; then
        echo "❌ '$CLIENT' in '$NAMESPACE' still reaches '$SERVER' on ${PORT}"
        echo "   A 'from' entry holding only a podSelector matches Pods in the policy's own namespace,"
        echo "   so it admits this one. Both selectors have to be in the same entry."
        exit 1
    fi
    sleep 3
done

echo "✅ '$CLIENT' is denied '$SERVER' on ${PORT} while '$ALLOWED' still gets through"
exit 0
