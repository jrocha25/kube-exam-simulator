#!/bin/bash
set -e

# The approved path works on the seeded state, so this is a constraint rather
# than an achievement and carries one mark. It is also the honest guard for the
# two deny checks: without it, replacing the policy with a deny-all would collect
# their eight marks for breaking the namespace.

NAMESPACE="net-array"
EDGE_NS="net-array-edge"
POLICY="array-ingress"
SERVER="station-relay"
CLIENT="edge-collector"
PORT="8443"
ATTEMPTS=4

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicies are not enforced on this cluster, so this question cannot be graded."
    echo "   Rebuild with: ./start.sh --stop && ./start.sh --rebuild"
    exit 1
fi

SERVER_IP=$(kubectl get pod "$SERVER" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null || true)
if [[ -z "$SERVER_IP" ]]; then
    echo "❌ Pod '$SERVER' in '$NAMESPACE' has no IP; it is part of the lab and should be Running"
    exit 1
fi
if [[ "$(kubectl get pod "$CLIENT" -n "$EDGE_NS" -o jsonpath='{.status.phase}' 2>/dev/null)" != "Running" ]]; then
    echo "❌ Pod '$CLIENT' in '$EDGE_NS' is not Running; it is part of the lab"
    exit 1
fi

REACHED=no
for _ in $(seq 1 $ATTEMPTS); do
    if kubectl exec -n "$EDGE_NS" "$CLIENT" -- timeout 4 bash -c "echo > /dev/tcp/${SERVER_IP}/${PORT}" >/dev/null 2>&1 </dev/null; then
        REACHED=yes
        break
    fi
    sleep 3
done

if [[ "$REACHED" != yes ]]; then
    echo "❌ '$CLIENT' in '$EDGE_NS' can no longer reach '$SERVER' on ${PORT}"
    echo "   It was working before the change and the question says it must keep working."
    exit 1
fi

echo "✅ '$CLIENT' still reaches '$SERVER' on ${PORT}"
exit 0
