#!/bin/bash
set -e

# The OR detector. A policy whose namespaceSelector and podSelector sit in two
# separate "from" entries admits probe-plain, because its namespace matches even
# though the Pod carries no label.
#
# Guarded twice: on the policy existing, and on the approved path still working.
# Without the second guard a deny-all policy -- which blocks everything, including
# what the question requires -- would collect this mark and the next.

NAMESPACE="net-tremor"
API_NS="net-tremor-api"
POLICY="tremor-ingress"
SERVER="tremor-ingest"
ALLOWED="gateway-allowed"
CLIENT="probe-plain"
PORT="8443"
ATTEMPTS=4

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicies are not enforced on this cluster, so this question cannot be graded."
    echo "   Rebuild with: ./start.sh --stop && ./start.sh --rebuild"
    exit 1
fi

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ NetworkPolicy '$POLICY' does not exist in namespace '$NAMESPACE'"
    exit 1
fi

SERVER_IP=$(kubectl get pod "$SERVER" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null || true)
if [[ -z "$SERVER_IP" ]]; then
    echo "❌ Pod '$SERVER' in '$NAMESPACE' has no IP; it is part of the lab and should be Running"
    exit 1
fi

probe() {
    local ns="$1" pod="$2" port="$3"
    kubectl exec -n "$ns" "$pod" -- timeout 4 bash -c "echo > /dev/tcp/${SERVER_IP}/${port}" >/dev/null 2>&1 </dev/null
}

if ! probe "$API_NS" "$ALLOWED" "$PORT"; then
    echo "❌ '$ALLOWED' cannot reach '$SERVER' on ${PORT} either, so nothing is being allowed through"
    echo "   A policy that denies everything is not a policy that scopes this port."
    exit 1
fi

for _ in $(seq 1 $ATTEMPTS); do
    if probe "$API_NS" "$CLIENT" "$PORT"; then
        echo "❌ '$CLIENT' in '$API_NS' reaches '$SERVER' on ${PORT}, and it must not"
        echo "   It is in the right namespace but carries no station-role=gateway label. When the"
        echo "   namespaceSelector and the podSelector are separate 'from' entries they are ORed,"
        echo "   so matching the namespace alone is enough to get in."
        exit 1
    fi
    sleep 3
done

echo "✅ '$CLIENT' is denied '$SERVER' on ${PORT} while '$ALLOWED' still gets through"
exit 0
