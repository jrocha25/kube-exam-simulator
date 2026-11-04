#!/bin/bash
set -e

ANSWER_FILE="/tmp/exam/q11/gatewayclass.txt"

if [[ ! -f "$ANSWER_FILE" ]]; then
    echo "❌ '$ANSWER_FILE' not found"
    exit 1
fi

CONTENT=$(tr -d '[:space:]' < "$ANSWER_FILE")
if [[ -z "$CONTENT" ]]; then
    echo "❌ '$ANSWER_FILE' is empty"
    exit 1
fi

EXPECTED=$(kubectl get gatewayclass -o json | jq -r '[.items[]
    | select([.status.conditions[]? | select(.type == "Accepted" and .status == "True")] | length > 0)
    | .spec.controllerName] | first // empty')

if [[ -z "$EXPECTED" ]]; then
    echo "❌ No accepted GatewayClass found in the cluster, cannot verify the answer"
    exit 1
fi

if [[ "$CONTENT" != "$EXPECTED" ]]; then
    echo "❌ Incorrect controller name. Expected '$EXPECTED', got '$CONTENT'"
    exit 1
fi

echo "✅ '$ANSWER_FILE' contains the controller name of the accepted GatewayClass"
exit 0
