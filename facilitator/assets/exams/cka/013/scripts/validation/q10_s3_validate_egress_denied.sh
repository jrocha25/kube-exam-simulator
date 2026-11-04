#!/bin/bash
set -e

# probe <namespace> <deployment> <ip> <port>: one TCP connect, 4 second cap.
probe() {
    kubectl exec -n "$1" deploy/"$2" -- timeout 4 bash -c "echo > /dev/tcp/$3/$4" >/dev/null 2>&1
}
pod_ip() {
    kubectl get pods -n "$1" -l app="$2" -o jsonpath='{.items[0].status.podIP}' 2>/dev/null
}

if ! kubectl get networkpolicy tally-egress -n net-tally >/dev/null 2>&1; then
    echo "❌ NetworkPolicy 'tally-egress' not found"
    exit 1
fi

LEDGER=$(pod_ip net-tally-data ledger)
AUDIT=$(pod_ip net-tally-data audit)
DECOY=$(pod_ip net-tally-sandbox ledger-decoy)
KIOSK=$(pod_ip net-tally-front kiosk)

# Allowed path first: a policy that denies everything would pass every check
# below for breaking the application.
if ! probe net-tally tally-api "$LEDGER" 5432; then
    echo "❌ tally-api cannot reach the ledger on pg-wire, so the deny checks prove nothing"
    exit 1
fi

for target in "$LEDGER:5433:the ledger's pg-admin port" \
              "$AUDIT:5432:a non-ledger Pod in net-tally-data" \
              "$DECOY:5432:a ledger in a namespace without tier=data" \
              "$KIOSK:80:a Pod in net-tally-front"; do
    IFS=: read -r ip port what <<<"$target"
    if probe net-tally tally-api "$ip" "$port"; then
        echo "❌ tally-api can still reach $what ($ip:$port)"
        exit 1
    fi
done

echo "✅ tally-api cannot reach other ports, non-ledger Pods or ledgers outside tier=data"
exit 0
