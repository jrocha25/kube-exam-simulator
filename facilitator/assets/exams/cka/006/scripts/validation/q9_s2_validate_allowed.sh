#!/bin/bash
set -e

NAMESPACE="net-orders"
POLICY="orders-lockdown"

# Guard first. On a cluster with no policy at all every Pod can reach every other
# Pod, so the connectivity test below would pass without any work having been
# done. The reachability only means something once the policy exists.
if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ NetworkPolicy '$POLICY' does not exist, so nothing is being enforced"
    exit 1
fi

IP=$(kubectl get pod orders -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null || true)
if [[ -z "$IP" ]]; then
    echo "❌ The 'orders' Pod has no IP address"
    exit 1
fi

if ! kubectl exec -n "$NAMESPACE" gateway -- \
        wget -qO- --timeout=8 "http://${IP}:80" 2>/dev/null | grep -qi "nginx\|<html"; then
    echo "❌ The 'gateway' Pod cannot reach 'orders' on port 80, but the policy must allow it"
    exit 1
fi

echo "✅ The 'gateway' Pod can reach 'orders' on port 80"
exit 0
