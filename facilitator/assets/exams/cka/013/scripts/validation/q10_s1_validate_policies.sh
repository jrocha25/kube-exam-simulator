#!/bin/bash
set -e

NAMESPACE="net-tally"

check_policy() {
    local name="$1" type="$2" json
    json=$(kubectl get networkpolicy "$name" -n "$NAMESPACE" -o json 2>/dev/null || true)
    if [[ -z "$json" ]]; then
        echo "❌ NetworkPolicy '$name' not found in '$NAMESPACE'"
        exit 1
    fi
    if [[ "$(echo "$json" | jq -c '.spec.podSelector')" != '{"matchLabels":{"app":"tally-api"}}' ]]; then
        echo "❌ '$name' does not select exactly the Pods labelled app=tally-api"
        exit 1
    fi
    if [[ "$(echo "$json" | jq -c '.spec.policyTypes')" != "[\"$type\"]" ]]; then
        echo "❌ '$name' has policyTypes $(echo "$json" | jq -c '.spec.policyTypes'), expected [\"$type\"]"
        exit 1
    fi
}

check_policy tally-egress Egress
check_policy tally-ingress Ingress

echo "✅ tally-egress and tally-ingress select tally-api with the right policy types"
exit 0
