#!/bin/bash

set -e

# The zone layout is 2 nodes in one zone and 1 in the other, so a hostname-only
# spread does not imply a zone-balanced one. With 4 replicas and DoNotSchedule at
# maxSkew 1, the only admissible split is 2/2 -- and both zones must be occupied.

NAMESPACE="sched-spread"
DEPLOYMENT="parcel-tracker"
ZONE_KEY="topology.kubernetes.io/zone"

if [[ -f /tmp/exam/insufficient-nodes ]]; then
    echo "❌ This cluster has fewer than 3 schedulable nodes, so the spread cannot be graded"
    echo "   See the shared setup warnings in the exam logs."
    exit 1
fi

READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2> /dev/null || true)
if [[ "$READY" != "4" ]]; then
    echo "❌ '$DEPLOYMENT' is not fully ready (${READY:-0}/4), so its distribution proves nothing yet"
    exit 1
fi

# Map every running Pod onto the zone label of the node it landed on.
ZONES=""
while read -r NODE; do
    [[ -z "$NODE" ]] && continue
    # Read through jq rather than jsonpath: the label key contains both dots and
    # a slash, and quoting that correctly in a jsonpath expression is a trap.
    ZONE=$(kubectl get node "$NODE" -o json 2> /dev/null | jq -r --arg k "$ZONE_KEY" '.metadata.labels[$k] // ""' || true)
    ZONES+="${ZONE:-unlabelled}"$'\n'
done < <(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" \
    --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}')

COUNTS=$(echo "$ZONES" | grep -v '^$' | sort | uniq -c | awk '{print $1}')
DISTINCT=$(echo "$ZONES" | grep -v '^$' | sort -u | wc -l)

if [[ "$DISTINCT" -lt 2 ]]; then
    echo "❌ All replicas landed in a single zone; the zone constraint is not being satisfied"
    exit 1
fi

MAX=$(echo "$COUNTS" | sort -n | tail -n 1)
MIN=$(echo "$COUNTS" | sort -n | head -n 1)
if [[ $((MAX - MIN)) -gt 1 ]]; then
    echo "❌ Zone distribution is skewed by $((MAX - MIN)) (max ${MAX}, min ${MIN}); maxSkew is 1"
    exit 1
fi

echo "✅ The 4 replicas are spread across $DISTINCT zones within a skew of 1"
exit 0
