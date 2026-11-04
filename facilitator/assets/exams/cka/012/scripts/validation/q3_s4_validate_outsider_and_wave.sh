#!/bin/bash
set -e

# The other half of the OR detector, plus the second rule.
#
#   gateway-outsider  carries the right Pod label in the WRONG namespace -> denied
#   wave-any          its whole namespace is allowed, but only on 9100
#
# A policy with two separate "from" entries admits gateway-outsider; a policy
# whose two rules were merged into one (both namespaces, both ports) admits
# wave-any on 8443. Three probes, three attempts each: four would risk the
# 90-second cap on exactly the answers that are wrong.

NAMESPACE="net-tremor"
WAVE_NS="net-tremor-wave"
API_NS="net-tremor-api"
POLICY="tremor-ingress"
SERVER="tremor-ingest"
ALLOWED="gateway-allowed"
OUTSIDER="gateway-outsider"
WAVE="wave-any"
ATTEMPTS=3

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

if ! probe "$API_NS" "$ALLOWED" 8443; then
    echo "❌ '$ALLOWED' cannot reach '$SERVER' on 8443, so nothing is being allowed through"
    echo "   A policy that denies everything is not a policy that scopes these ports."
    exit 1
fi

for _ in $(seq 1 $ATTEMPTS); do
    if probe "$NAMESPACE" "$OUTSIDER" 8443; then
        echo "❌ '$OUTSIDER' reaches '$SERVER' on 8443, and it must not"
        echo "   It carries station-role=gateway but runs in '$NAMESPACE', whose namespace label does not match."
        exit 1
    fi
    sleep 3
done

REACHED=no
for _ in $(seq 1 $ATTEMPTS); do
    if probe "$WAVE_NS" "$WAVE" 9100; then REACHED=yes; break; fi
    sleep 3
done
if [[ "$REACHED" != yes ]]; then
    echo "❌ '$WAVE' in '$WAVE_NS' cannot reach '$SERVER' on 9100, but every Pod in that namespace must"
    exit 1
fi

for _ in $(seq 1 $ATTEMPTS); do
    if probe "$WAVE_NS" "$WAVE" 8443; then
        echo "❌ '$WAVE' reaches '$SERVER' on 8443 as well, and only 9100 is open to it"
        echo "   A single rule listing both sources and both ports permits every combination of them."
        exit 1
    fi
    sleep 3
done

echo "✅ '$OUTSIDER' is denied 8443, and '$WAVE' reaches 9100 but not 8443"
exit 0
