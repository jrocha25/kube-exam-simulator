#!/bin/bash
set -e

NAMESPACE="pilot-ops"
DEPLOYMENT="pilot-dispatch"
PC="berth-urgent"

if [[ "$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.priorityClassName}' 2>/dev/null)" != "$PC" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' does not use the PriorityClass $PC"
    exit 1
fi

VALUE=$(kubectl get priorityclass "$PC" -o jsonpath='{.value}' 2>/dev/null || true)
if [[ -z "$VALUE" ]]; then
    echo "❌ PriorityClass '$PC' does not exist"
    exit 1
fi

OK=no
for _ in $(seq 1 12); do
    PODS=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" -o json \
        | jq -r '[.items[] | select(.metadata.deletionTimestamp == null)]')
    TOTAL=$(echo "$PODS" | jq 'length')
    GOOD=$(echo "$PODS" | jq --arg pc "$PC" --argjson v "$VALUE" \
        '[.[] | select(.spec.priorityClassName == $pc and .spec.priority == $v and .status.phase == "Running")] | length')
    if [[ "$TOTAL" == "2" && "$GOOD" == "2" ]]; then
        OK=yes
        break
    fi
    sleep 5
done
if [[ "$OK" != yes ]]; then
    echo "❌ '$DEPLOYMENT' does not run 2 Pods with priority $VALUE ($GOOD of $TOTAL)"
    exit 1
fi

echo "✅ Both Pods of '$DEPLOYMENT' run with priority $VALUE"
exit 0
