#!/bin/bash

set -e

# 'scanner' is denied before the candidate touches anything, so this only counts
# once the allowed path works too. Without that precondition an untouched
# cluster would score here for doing nothing.
#
# It is also the check that catches the lazy repair: widening the rule to the
# whole clients namespace fixes checkout and lets scanner in with it.

NAMESPACE="np-ts-selector"
CLIENT_NS="np-ts-selector-clients"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so this check cannot mean anything"
    exit 1
fi

INVENTORY_IP=$(kubectl get pod inventory -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$INVENTORY_IP" ]]; then
    echo "❌ Pod 'inventory' in '$NAMESPACE' has no IP address"
    exit 1
fi

CHECKOUT=$(kubectl get pod -n "$CLIENT_NS" -l app=checkout \
    --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}' 2> /dev/null || true)
if [[ -z "$CHECKOUT" ]]; then
    echo "❌ No running 'checkout' Pod found in '$CLIENT_NS'"
    exit 1
fi

ALLOWED="no"
for _ in $(seq 1 6); do
    if kubectl exec "$CHECKOUT" -n "$CLIENT_NS" --request-timeout=60s -- \
            wget -q -T 5 -t 1 -O- "http://${INVENTORY_IP}:80" > /dev/null 2>&1; then
        ALLOWED="yes"
        break
    fi
    sleep 5
done

if [[ "$ALLOWED" != "yes" ]]; then
    echo "❌ 'checkout' still cannot reach 'inventory', so the fault has not been repaired"
    exit 1
fi

if kubectl exec scanner -n "$CLIENT_NS" --request-timeout=60s -- \
        wget -q -T 5 -t 1 -O- "http://${INVENTORY_IP}:80" > /dev/null 2>&1; then
    echo "❌ Pod 'scanner' can now reach 'inventory'; the repair opened the rule too far"
    exit 1
fi

echo "✅ 'checkout' reaches 'inventory' while 'scanner' remains shut out"
exit 0
