#!/bin/bash

set -e

# A rule with neither a peer nor a port permits everything in that direction,
# which would satisfy the reachability checks while defeating the point of the
# design.

NAMESPACE="np-design"

COUNT=$(kubectl get networkpolicy -n "$NAMESPACE" -o json | jq '[.items[]] | length')
if [[ "$COUNT" == "0" ]]; then
    echo "❌ No NetworkPolicy exists in '$NAMESPACE', so nothing has been designed yet"
    exit 1
fi

OPEN=$(kubectl get networkpolicy -n "$NAMESPACE" -o json | jq '
    [ .items[].spec
      | (.ingress // [])[], (.egress // [])[]
      | select(((.to // []) | length) == 0 and ((.from // []) | length) == 0 and ((.ports // []) | length) == 0)
    ] | length')

if [[ "$OPEN" != "0" ]]; then
    echo "❌ A NetworkPolicy in '$NAMESPACE' contains a rule that permits all traffic"
    exit 1
fi

WIDE=$(kubectl get networkpolicy -n "$NAMESPACE" -o json | jq '
    [ .items[].spec
      | (.ingress // [])[], (.egress // [])[]
      | (.to // [])[], (.from // [])[]
      | select(.ipBlock.cidr == "0.0.0.0/0")
    ] | length')

if [[ "$WIDE" != "0" ]]; then
    echo "❌ A NetworkPolicy in '$NAMESPACE' opens a path to 0.0.0.0/0"
    exit 1
fi

echo "✅ No policy in '$NAMESPACE' contains a blanket allow rule"
exit 0
