#!/bin/bash
set -e

NODE01=$(grep '^node01=' /tmp/exam/nodes.env | cut -d= -f2)
IP=$(kubectl get node "$NODE01" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || true)
if [[ -z "$IP" ]]; then
    echo "❌ Cannot resolve node01's address"
    exit 1
fi

if [[ -z "$(kubectl get service tally-board-np -n tally -o name 2>/dev/null)" ]]; then
    echo "❌ Service 'tally-board-np' not found"
    exit 1
fi

for _ in 1 2 3 4; do
    if ssh -o ConnectTimeout=10 -o BatchMode=yes node01 "curl -s -m 4 http://$IP:30814/" </dev/null 2>/dev/null | grep -q 'Welcome to nginx'; then
        echo "✅ tally-board answers on http://$IP:30814"
        exit 0
    fi
    sleep 3
done

echo "❌ Nothing answers on http://$IP:30814"
exit 1
