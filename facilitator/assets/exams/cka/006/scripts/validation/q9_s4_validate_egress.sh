#!/bin/bash
set -e

NAMESPACE="net-orders"
POLICY="orders-lockdown"

JSON=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ NetworkPolicy '$POLICY' not found in namespace '$NAMESPACE'"
    exit 1
fi

# The ledger backend must be reachable, proven by traffic rather than by reading
# the rule -- the point of the question is that declaring Egress denies everything
# not named, so a policy that merely mentions the backend is not enough.
LEDGER_IP=$(kubectl get pod ledger -n net-ledger -o jsonpath='{.status.podIP}' 2>/dev/null || true)
if [[ -z "$LEDGER_IP" ]]; then
    echo "❌ The 'ledger' Pod in net-ledger has no IP address"
    exit 1
fi

if ! kubectl exec -n "$NAMESPACE" orders -- \
        timeout 10 bash -c "exec 3<>/dev/tcp/${LEDGER_IP}/80 && echo ok" >/dev/null 2>&1; then
    echo "❌ 'orders' cannot reach the ledger backend on port 80"
    exit 1
fi

# DNS: assert the rule rather than resolving a name. Question 8 takes cluster DNS
# down, and this question must be gradeable whether or not that one was solved.
DNS_UDP=$(echo "$JSON" | jq '[.spec.egress[]?.ports[]? | select(.port == 53 and (.protocol // "TCP") == "UDP")] | length')
DNS_TCP=$(echo "$JSON" | jq '[.spec.egress[]?.ports[]? | select(.port == 53 and (.protocol // "TCP") == "TCP")] | length')

if [[ "${DNS_UDP:-0}" -lt 1 ]]; then
    echo "❌ '$POLICY' has no egress rule permitting UDP port 53 -- the orders Pod cannot resolve names"
    exit 1
fi
if [[ "${DNS_TCP:-0}" -lt 1 ]]; then
    echo "❌ '$POLICY' has no egress rule permitting TCP port 53"
    exit 1
fi

# "Nothing else may leave it": an empty 'to' with no ports is an allow-all.
OPEN=$(echo "$JSON" | jq '[.spec.egress[]? | select((.to // []) == [] and (.ports // []) == [])] | length')
if [[ "${OPEN:-0}" -gt 0 ]]; then
    echo "❌ '$POLICY' contains an egress rule that permits all outbound traffic"
    exit 1
fi

echo "✅ Egress reaches the ledger backend and permits cluster DNS over UDP and TCP 53"
exit 0
