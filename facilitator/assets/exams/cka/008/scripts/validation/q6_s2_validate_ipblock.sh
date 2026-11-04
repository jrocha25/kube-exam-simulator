#!/bin/bash

set -e

# Graded on the spec rather than by live traffic: neither the public internet nor
# 169.254.169.254 is reachable from this cluster in the first place, so a probe
# would fail identically whether or not the candidate wrote anything.
#
# The whole ipBlock must live in ONE rule together with the port, otherwise the
# exclusions and the port restriction apply to different traffic.

NAMESPACE="np-external"
POLICY="gateway-egress"
POD_CIDR="10.42.0.0/16"
METADATA_CIDR="169.254.169.254/32"

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json)

MATCHING=$(echo "$SPEC" | jq --arg pod "$POD_CIDR" --arg meta "$METADATA_CIDR" '
    [ .spec.egress[]?
      | select(
          ([.to[]? | select(.ipBlock.cidr == "0.0.0.0/0")] | length) == 1
          and ([.to[]?] | length) == 1
          and ([.to[]?.ipBlock.except[]? | select(. == $pod)] | length) == 1
          and ([.to[]?.ipBlock.except[]? | select(. == $meta)] | length) == 1
          and ([.ports[]? | select(.port == 443 and (.protocol // "TCP") == "TCP")] | length) == 1
          and ([.ports[]?] | length) == 1
        )
    ] | length')

if [[ "$MATCHING" != "1" ]]; then
    echo "❌ '$POLICY' has no single egress rule allowing TCP 443 to 0.0.0.0/0 while excluding $POD_CIDR and $METADATA_CIDR"
    exit 1
fi

echo "✅ '$POLICY' permits TCP 443 to 0.0.0.0/0 except $POD_CIDR and $METADATA_CIDR"
exit 0
