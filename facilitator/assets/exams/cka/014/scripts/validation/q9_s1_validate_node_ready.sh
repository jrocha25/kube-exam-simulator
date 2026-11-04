#!/bin/bash
set -e

NODE03=$(grep '^node03=' /tmp/exam/nodes.env | cut -d= -f2)
if [[ -z "$NODE03" ]]; then
    echo "❌ Setup did not record node03's name"
    exit 1
fi

READY=""
for _ in $(seq 1 6); do
    READY=$(kubectl get node "$NODE03" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$READY" == "True" ]] && break
    sleep 5
done
if [[ "$READY" != "True" ]]; then
    echo "❌ node03 ($NODE03) is not Ready"
    exit 1
fi

if [[ "$(kubectl get node "$NODE03" -o jsonpath='{.spec.unschedulable}')" == "true" ]]; then
    echo "❌ node03 is Ready but cordoned"
    exit 1
fi

echo "✅ node03 is Ready and schedulable"
exit 0
