#!/bin/bash
set -e

NAMESPACE="net-guard"
POLICY="backend-ingress"

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' not found in namespace '$NAMESPACE'"
    exit 1
fi

POLICY_JSON=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json)

POD_SELECTOR=$(echo "$POLICY_JSON" | jq -r '.spec.podSelector.matchLabels.app // ""')
if [[ "$POD_SELECTOR" != "backend" ]]; then
    echo "❌ NetworkPolicy must select Pods with the label app=backend (got: 'app=$POD_SELECTOR')"
    exit 1
fi

POLICY_TYPES=$(echo "$POLICY_JSON" | jq -r '.spec.policyTypes // [] | sort | join(",")')
if [[ "$POLICY_TYPES" != "Ingress" ]]; then
    echo "❌ policyTypes must contain only 'Ingress' (got: '$POLICY_TYPES')"
    exit 1
fi

RULE_COUNT=$(echo "$POLICY_JSON" | jq '.spec.ingress // [] | length')
if [[ "$RULE_COUNT" != "1" ]]; then
    echo "❌ Expected exactly one ingress rule, found $RULE_COUNT"
    exit 1
fi

FROM_COUNT=$(echo "$POLICY_JSON" | jq '.spec.ingress[0].from // [] | length')
if [[ "$FROM_COUNT" != "1" ]]; then
    echo "❌ The ingress rule must have exactly one 'from' entry, found $FROM_COUNT"
    exit 1
fi

FROM_SELECTOR=$(echo "$POLICY_JSON" | jq -r '.spec.ingress[0].from[0].podSelector.matchLabels.app // ""')
if [[ "$FROM_SELECTOR" != "frontend" ]]; then
    echo "❌ The ingress rule must allow Pods with the label app=frontend (got: 'app=$FROM_SELECTOR')"
    exit 1
fi

PORT_COUNT=$(echo "$POLICY_JSON" | jq '.spec.ingress[0].ports // [] | length')
if [[ "$PORT_COUNT" != "1" ]]; then
    echo "❌ The ingress rule must have exactly one port entry, found $PORT_COUNT"
    exit 1
fi

PORT=$(echo "$POLICY_JSON" | jq -r '.spec.ingress[0].ports[0].port')
if [[ "$PORT" != "80" ]]; then
    echo "❌ Incorrect port. Expected '80', got '$PORT'"
    exit 1
fi

PROTOCOL=$(echo "$POLICY_JSON" | jq -r '.spec.ingress[0].ports[0].protocol // "TCP"')
if [[ "$PROTOCOL" != "TCP" ]]; then
    echo "❌ Incorrect protocol. Expected 'TCP', got '$PROTOCOL'"
    exit 1
fi

echo "✅ NetworkPolicy '$POLICY' is configured correctly"
exit 0
