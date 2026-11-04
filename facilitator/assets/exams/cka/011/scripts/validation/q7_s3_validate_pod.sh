#!/bin/bash
set -e

NAMESPACE="dns-apron"
POD="briefing"

if ! kubectl get pod "$POD" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

for _ in $(seq 1 8); do
    PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$PHASE" == "Running" ]] && break
    sleep 5
done
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ Pod '$POD' is ${PHASE:-absent}, expected Running"
    exit 1
fi

POLICY=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.dnsPolicy}' 2>/dev/null || true)
if [[ "$POLICY" != "ClusterFirst" ]]; then
    echo "❌ Pod '$POD' uses dnsPolicy '${POLICY:-unset}', expected 'ClusterFirst'"
    exit 1
fi

echo "✅ Pod '$POD' is running with the ClusterFirst DNS policy"
exit 0
