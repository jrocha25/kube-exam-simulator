#!/bin/bash
set -e

NAME="orbit-range"

JSON=$(kubectl get servicecidr "$NAME" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ ServiceCIDR '$NAME' not found"
    exit 1
fi

if [[ "$(echo "$JSON" | jq -c '.spec.cidrs')" != '["10.250.0.0/24"]' ]]; then
    echo "❌ '$NAME' covers $(echo "$JSON" | jq -c '.spec.cidrs'), expected [\"10.250.0.0/24\"]"
    exit 1
fi
if [[ "$(echo "$JSON" | jq -r '.status.conditions[]? | select(.type == "Ready") | .status')" != "True" ]]; then
    echo "❌ '$NAME' is not Ready"
    exit 1
fi

echo "✅ ServiceCIDR '$NAME' covers 10.250.0.0/24 and is Ready"
exit 0
