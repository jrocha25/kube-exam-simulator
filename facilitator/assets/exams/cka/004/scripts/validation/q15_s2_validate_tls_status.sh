#!/bin/bash
set -e

NAMESPACE="edge-tls"
GATEWAY="tls-gw"

if ! kubectl get gateway "$GATEWAY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Gateway '$GATEWAY' not found in namespace '$NAMESPACE'"
    exit 1
fi

PROGRAMMED=""
RESOLVED=""
for _ in $(seq 1 12); do
    PROGRAMMED=$(kubectl get gateway "$GATEWAY" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)
    RESOLVED=$(kubectl get gateway "$GATEWAY" -n "$NAMESPACE" -o json \
        | jq -r '[.status.listeners[]? | select(.name == "https") | .conditions[]? | select(.type == "ResolvedRefs" and .status == "True")] | length' 2>/dev/null || true)
    if [[ "$PROGRAMMED" == "True" ]] && [[ -n "$RESOLVED" ]] && [[ "$RESOLVED" != "0" ]]; then
        break
    fi
    sleep 5
done

if [[ "$PROGRAMMED" != "True" ]]; then
    echo "❌ Gateway '$GATEWAY' is not Programmed by the controller (status: '${PROGRAMMED:-<none>}')"
    exit 1
fi

if [[ -z "$RESOLVED" ]] || [[ "$RESOLVED" == "0" ]]; then
    echo "❌ The 'https' listener cannot resolve its certificate reference"
    exit 1
fi

echo "✅ The 'https' listener is programmed and its certificate reference resolves"
exit 0
