#!/bin/bash

set -e

# The exclusions are only worth anything if no other rule quietly re-opens them.
# A second rule with no 'to' and no 'ports' permits everything; a second ipBlock
# of 0.0.0.0/0 without the same 'except' list does the same for the addresses
# that were meant to be blocked.

NAMESPACE="np-external"
POLICY="gateway-egress"
POD_CIDR="10.42.0.0/16"
METADATA_CIDR="169.254.169.254/32"

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json)

OPEN=$(echo "$SPEC" | jq '[.spec.egress[]? | select(((.to // []) | length) == 0 and ((.ports // []) | length) == 0)] | length')
if [[ "$OPEN" != "0" ]]; then
    echo "❌ '$POLICY' contains a rule that permits all egress traffic"
    exit 1
fi

LEAKY=$(echo "$SPEC" | jq --arg pod "$POD_CIDR" --arg meta "$METADATA_CIDR" '
    [ .spec.egress[]?.to[]?
      | select(.ipBlock != null)
      | select(
          ([.ipBlock.except[]? | select(. == $pod)] | length) == 0
          or ([.ipBlock.except[]? | select(. == $meta)] | length) == 0
        )
    ] | length')

if [[ "$LEAKY" != "0" ]]; then
    echo "❌ '$POLICY' has an ipBlock that does not exclude both $POD_CIDR and $METADATA_CIDR"
    exit 1
fi

echo "✅ No rule in '$POLICY' re-opens a path to the excluded ranges"
exit 0
