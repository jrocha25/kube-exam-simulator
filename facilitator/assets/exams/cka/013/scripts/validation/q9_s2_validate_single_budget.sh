#!/bin/bash
set -e

NAMESPACE="wl-quorum"

# A budget covers the quorum Pods when its selector matches their labels. Ask
# the API server rather than parsing selectors: list each budget's matches.
POD_LABELS=$(kubectl get pods -n "$NAMESPACE" -l app=quorum,ring=primary -o name 2>/dev/null | head -1)
if [[ -z "$POD_LABELS" ]]; then
    echo "❌ No quorum Pods are running"
    exit 1
fi

COVERING=()
for PDB in $(kubectl get pdb -n "$NAMESPACE" -o jsonpath='{.items[*].metadata.name}'); do
    SEL=$(kubectl get pdb "$PDB" -n "$NAMESPACE" -o json | jq -r '.spec.selector as $s
        | ([($s.matchLabels // {}) | to_entries[] | "\(.key)=\(.value)"]
           + [($s.matchExpressions // [])[]
              | if .operator == "In" then "\(.key) in (\(.values | join(",")))"
                elif .operator == "NotIn" then "\(.key) notin (\(.values | join(",")))"
                elif .operator == "Exists" then .key
                else "!\(.key)" end])
        | join(",")')
    if [[ -n "$(kubectl get pods -n "$NAMESPACE" -l "app=quorum,ring=primary${SEL:+,$SEL}" -o name 2>/dev/null)" ]]; then
        COVERING+=("$PDB")
    fi
done

if [[ "${COVERING[*]}" != "quorum-budget" ]]; then
    echo "❌ The quorum Pods are covered by: ${COVERING[*]:-no budget}; expected quorum-budget alone"
    exit 1
fi

echo "✅ quorum-budget is the only budget covering the quorum Pods"
exit 0
