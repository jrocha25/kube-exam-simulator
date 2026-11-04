#!/bin/bash
set -e

# probe <namespace> <deployment> <ip> <port>: one TCP connect, 4 second cap.
probe() {
    kubectl exec -n "$1" deploy/"$2" -- timeout 4 bash -c "echo > /dev/tcp/$3/$4" >/dev/null 2>&1
}
pod_ip() {
    kubectl get pods -n "$1" -l app="$2" -o jsonpath='{.items[0].status.podIP}' 2>/dev/null
}

if ! kubectl get networkpolicy tally-ingress -n net-tally >/dev/null 2>&1; then
    echo "❌ NetworkPolicy 'tally-ingress' not found"
    exit 1
fi

API=$(pod_ip net-tally tally-api)
if [[ -z "$API" ]]; then
    echo "❌ tally-api is not running"
    exit 1
fi

OK=no
for _ in $(seq 1 6); do
    probe net-tally-front teller "$API" 80 && { OK=yes; break; }
    sleep 5
done
if [[ "$OK" != yes ]]; then
    echo "❌ teller cannot reach tally-api on port 80"
    exit 1
fi

if probe net-tally-front kiosk "$API" 80; then
    echo "❌ kiosk (role=kiosk) can still reach tally-api"
    exit 1
fi
if probe net-tally-data ledger "$API" 80; then
    echo "❌ Pods outside net-tally-front can still reach tally-api"
    exit 1
fi

echo "✅ Only teller Pods from net-tally-front reach tally-api"
exit 0
