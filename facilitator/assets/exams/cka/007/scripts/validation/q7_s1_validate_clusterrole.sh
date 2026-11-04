#!/bin/bash
set -e

CLUSTERROLE="endpoint-prober"

if ! kubectl get clusterrole "$CLUSTERROLE" &> /dev/null; then
    echo "❌ ClusterRole '$CLUSTERROLE' not found"
    exit 1
fi

RULES=$(kubectl get clusterrole "$CLUSTERROLE" -o json)

for url in "/healthz" "/healthz/*" "/livez" "/version" "/metrics"; do
    FOUND=$(echo "$RULES" | jq --arg u "$url" '
        [.rules[]
         | select(((.nonResourceURLs // []) | index($u)))
         | select(((.verbs // []) | index("get") or index("*")))] | length')
    if [[ "$FOUND" == "0" ]]; then
        echo "❌ ClusterRole '$CLUSTERROLE' does not allow 'get' on the non-resource URL '$url'"
        exit 1
    fi
done

# A nonResourceURLs rule cannot carry resources; if one does, the object is not
# what was asked for.
MIXED=$(echo "$RULES" | jq '[.rules[] | select(((.nonResourceURLs // []) | length) > 0) | select(((.resources // []) | length) > 0)] | length')
if [[ "$MIXED" != "0" ]]; then
    echo "❌ ClusterRole '$CLUSTERROLE' mixes nonResourceURLs and resources in the same rule"
    exit 1
fi

echo "✅ ClusterRole '$CLUSTERROLE' grants 'get' on the five health and metrics endpoints"
exit 0
