#!/bin/bash
set -e

NAMESPACE="net-egress"

if ! kubectl exec frontend -n "$NAMESPACE" --request-timeout=60s -- \
        wget -q -T 5 -t 1 -O- "http://backend" > /dev/null 2>&1; then
    echo "❌ Pod 'frontend' cannot fetch 'http://backend'"
    exit 1
fi

echo "✅ Pod 'frontend' can fetch 'http://backend'"
exit 0
