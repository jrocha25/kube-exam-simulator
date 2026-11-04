#!/bin/bash
set -e

# Guarded on the candidate's policy existing. Without that guard "gateway-allowed
# reaches 8443" is true of a namespace with no policy at all, and this would be
# three marks handed over for an untouched cluster -- the trap CLAUDE.md records
# from cka/011 and cka/008.
#
# The probe runs from the Pod the question names. A client this script created
# would not be selected by the candidate's policy and would prove nothing.
#
# Four attempts, not twelve: twelve times a four-second connect plus a five-second
# sleep is 108 seconds and would be killed by the 90-second script cap.

NAMESPACE="net-tremor"
API_NS="net-tremor-api"
POLICY="tremor-ingress"
SERVER="tremor-ingest"
CLIENT="gateway-allowed"
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
if [[ "$(kubectl get pod "$CLIENT" -n "$API_NS" -o jsonpath='{.status.phase}' 2>/dev/null)" != "Running" ]]; then
    echo "❌ Pod '$CLIENT' in '$API_NS' is not Running; it is part of the lab"
    exit 1
fi

REACHED=no
for _ in $(seq 1 $ATTEMPTS); do
    if kubectl exec -n "$API_NS" "$CLIENT" -- timeout 4 bash -c "echo > /dev/tcp/${SERVER_IP}/${PORT}" >/dev/null 2>&1 </dev/null; then
        REACHED=yes
        break
    fi
    sleep 3
done

if [[ "$REACHED" != yes ]]; then
    echo "❌ '$CLIENT' in '$API_NS' cannot reach '$SERVER' on ${PORT}, but it is the one client that must"
    echo "   Its namespace carries seismo.io/tier=api and the Pod carries station-role=gateway."
    exit 1
fi

echo "✅ '$CLIENT' reaches '$SERVER' on ${PORT}"
exit 0
