#!/bin/bash
set -e

NAMESPACE="net-egress"

OTHER_IP=$(kubectl get pod other -n "$NAMESPACE" -o jsonpath='{.status.podIP}')
if [[ -z "$OTHER_IP" ]]; then
    echo "❌ Pod 'other' has no IP address"
    exit 1
fi

if kubectl exec frontend -n "$NAMESPACE" --request-timeout=60s -- \
        wget -q -T 5 -t 1 -O- "http://$OTHER_IP:80" > /dev/null 2>&1; then
    echo "❌ Pod 'frontend' can reach 'other'; egress is no longer restricted"
    exit 1
fi

echo "✅ Pod 'frontend' is still unable to reach anything but the backend"
exit 0
