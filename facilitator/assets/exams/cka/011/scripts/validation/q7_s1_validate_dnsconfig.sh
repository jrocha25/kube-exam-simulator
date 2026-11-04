#!/bin/bash
set -e

NAMESPACE="dns-apron"
POD="briefing"
SEARCH="dns-apron-wx.svc.cluster.local"

if ! kubectl get pod "$POD" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json)

if ! jq -e --arg s "$SEARCH" '(.spec.dnsConfig.searches // []) | index($s)' <<<"$JSON" >/dev/null; then
    FOUND=$(jq -r '(.spec.dnsConfig.searches // []) | join(", ")' <<<"$JSON")
    echo "❌ Pod '$POD' does not list '${SEARCH}' among its DNS search domains"
    echo "   Found: ${FOUND:-none}"
    exit 1
fi

if ! jq -e '(.spec.dnsConfig.options // []) | any(.name == "ndots" and .value == "1")' <<<"$JSON" >/dev/null; then
    FOUND=$(jq -r '(.spec.dnsConfig.options // []) | map("\(.name)=\(.value // "")") | join(", ")' <<<"$JSON")
    echo "❌ Pod '$POD' does not set the DNS option ndots to 1"
    echo "   Found: ${FOUND:-none}"
    exit 1
fi

echo "✅ Pod '$POD' declares the required search domain and ndots option"
exit 0
