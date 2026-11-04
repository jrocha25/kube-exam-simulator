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
    echo "❌ NetworkPolicy 'tally-egress' not found; an unrestricted Pod proves nothing"
    exit 1
fi

LEDGER=$(pod_ip net-tally-data ledger)
REPLICA=$(pod_ip net-tally-data ledger-replica)
if [[ -z "$LEDGER" || -z "$REPLICA" ]]; then
    echo "❌ The ledger Pods are not running"
    exit 1
fi

OK=no
for _ in $(seq 1 6); do
    if probe net-tally tally-api "$LEDGER" 5432 && probe net-tally tally-api "$REPLICA" 6432; then
        OK=yes
        break
    fi
    sleep 5
done
if [[ "$OK" != yes ]]; then
    echo "❌ tally-api cannot reach every ledger Pod on its pg-wire port (ledger:5432, ledger-replica:6432)"
    exit 1
fi

# A trailing dot makes the name absolute, so the search list cannot answer it.
if ! kubectl exec -n net-tally deploy/tally-api -- timeout 6 getent hosts ledger-db.net-tally-data.svc.cluster.local. >/dev/null 2>&1; then
    echo "❌ tally-api cannot resolve names through cluster DNS"
    exit 1
fi

echo "✅ tally-api reaches both ledgers on pg-wire and resolves names"
exit 0
