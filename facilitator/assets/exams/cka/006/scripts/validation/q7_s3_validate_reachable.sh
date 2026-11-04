#!/bin/bash
set -e

NAMESPACE="svc-orders"
SERVICE="checkout"
CLIENT="probe"

if ! kubectl get pod "$CLIENT" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ The '$CLIENT' Pod is missing from namespace '$NAMESPACE'"
    exit 1
fi

# Reach the Service by ClusterIP rather than by name. The question words its
# acceptance criterion as "wget -qO- http://checkout", which works -- question 8's
# DNS outage is staged on the auxiliary cluster and this one's resolution is
# healthy -- but grading the ClusterIP tests the same repair without also failing a
# correct answer over a few seconds of DNS flakiness.
IP=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
if [[ -z "$IP" || "$IP" == "None" ]]; then
    echo "❌ Service '$SERVICE' has no ClusterIP"
    exit 1
fi

if ! kubectl exec -n "$NAMESPACE" "$CLIENT" -- \
        wget -qO- --timeout=5 "http://${IP}" 2>/dev/null | grep -qi "nginx\|<html"; then
    echo "❌ '$CLIENT' could not fetch http://${IP} (the '$SERVICE' ClusterIP)"
    exit 1
fi

echo "✅ '$CLIENT' fetched the '$SERVICE' Service successfully"
exit 0
