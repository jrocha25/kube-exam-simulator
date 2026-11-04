#!/bin/bash
set -e

NAMESPACE="wl-quorum"
PDB="quorum-budget"

JSON=$(kubectl get pdb "$PDB" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ PodDisruptionBudget '$PDB' not found in '$NAMESPACE'"
    exit 1
fi

# Both labels must be required. matchLabels and an equivalent pair of In
# expressions say the same thing, so normalise to one set of key=value pairs.
SELECTOR=$(echo "$JSON" | jq -c '.spec.selector as $s
    | ([($s.matchLabels // {}) | to_entries[] | "\(.key)=\(.value)"]
       + [($s.matchExpressions // [])[] | select(.operator == "In" and (.values | length) == 1) | "\(.key)=\(.values[0])"])
    | unique')
OTHER=$(echo "$JSON" | jq '[.spec.selector.matchExpressions // [] | .[] | select(.operator != "In" or (.values | length) != 1)] | length')
if [[ "$SELECTOR" != '["app=quorum","ring=primary"]' || "$OTHER" != "0" ]]; then
    echo "❌ '$PDB' selects $(echo "$JSON" | jq -c .spec.selector), expected app=quorum and ring=primary"
    exit 1
fi

if [[ "$(echo "$JSON" | jq -r '.spec.maxUnavailable // empty')" != "1" ]]; then
    echo "❌ '$PDB' does not set maxUnavailable: 1"
    exit 1
fi
if [[ "$(echo "$JSON" | jq -r '.spec.minAvailable // empty')" != "" ]]; then
    echo "❌ '$PDB' sets minAvailable as well"
    exit 1
fi
if [[ "$(echo "$JSON" | jq -r '.spec.unhealthyPodEvictionPolicy // empty')" != "AlwaysAllow" ]]; then
    echo "❌ '$PDB' does not let running-but-unready Pods be evicted regardless of the budget"
    exit 1
fi

echo "✅ '$PDB' selects both labels, allows 1 unavailable and always allows unhealthy evictions"
exit 0
