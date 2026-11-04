#!/bin/bash
set -e

# Probed with bash's /dev/tcp: the nginx image ships no curl and no wget, and a
# client Pod created by this script would not be selected by the candidate's
# policy, so the probe has to come from the Pod the question already names.
#
# Four attempts, not twelve. Validation runs at the end of the exam, long after
# the policy was applied, so there is nothing left to converge; the retries only
# absorb a transient. A 12 x (4s connect + 5s sleep) loop would overrun the 90
# second script cap on exactly the answers that are wrong.

NAMESPACE="net-radar"
CLIENT="radar"
SERVER="archive"
PORT="6666"
ATTEMPTS=4

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicies are not enforced on this cluster, so this question cannot be graded."
    echo "   Rebuild with: ./start.sh --stop && ./start.sh --rebuild"
    exit 1
fi

for pod in "$CLIENT" "$SERVER"; do
    PHASE=$(kubectl get pod "$pod" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [[ "$PHASE" != "Running" ]]; then
        echo "❌ Pod '$pod' in '$NAMESPACE' is ${PHASE:-absent}, so connectivity cannot be tested"
        exit 1
    fi
done

# Guarded on the candidate's own policy existing. Without this, "radar can reach
# beacon on 5555" is true on a namespace with no policy at all and would hand
# over two marks for an untouched cluster -- the trap cka/008 q9 and q11
# document. The marks for this question have to require the work.
if ! kubectl get networkpolicy radar-egress -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ NetworkPolicy 'radar-egress' does not exist in namespace '$NAMESPACE'"
    exit 1
fi

SERVER_IP=$(kubectl get pod "$SERVER" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null || true)
if [[ -z "$SERVER_IP" ]]; then
    echo "❌ Pod '$SERVER' has no IP address"
    exit 1
fi

probe() {
    kubectl exec -n "$NAMESPACE" "$CLIENT" -- \
        timeout 4 bash -c "echo > /dev/tcp/${SERVER_IP}/${PORT}" >/dev/null 2>&1
}

REACHED=no
for _ in $(seq 1 $ATTEMPTS); do
    if probe; then REACHED=yes; break; fi
    sleep 3
done

if [[ "$REACHED" != yes ]]; then
    echo "❌ '$CLIENT' cannot reach '$SERVER' on port $PORT, which is approved traffic"
    exit 1
fi

echo "✅ '$CLIENT' reaches '$SERVER' on port $PORT"
exit 0
