#!/bin/bash

set -e

# Resolved live: whichever node the collector is on, every agent replica must be
# there too.

NAMESPACE="sched-podaff"
INFRA_NS="sched-podaff-infra"
DEPLOYMENT="depot-agent"
TARGET="depot-telemetry"

TARGET_NODE=$(kubectl get pods -n "$INFRA_NS" -l app="$TARGET" \
    --field-selector=status.phase=Running -o jsonpath='{.items[0].spec.nodeName}' 2> /dev/null || true)
if [[ -z "$TARGET_NODE" ]]; then
    echo "❌ No running '$TARGET' Pod found in '$INFRA_NS'; the question environment is incomplete"
    exit 1
fi

NODES=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" \
    --field-selector=status.phase=Running -o jsonpath='{range .items[*]}{.spec.nodeName}{"\n"}{end}')
if [[ -z "$NODES" ]]; then
    echo "❌ No running Pods found for '$DEPLOYMENT' (are they labelled app=$DEPLOYMENT?)"
    exit 1
fi

COUNT=0
while read -r NODE; do
    [[ -z "$NODE" ]] && continue
    if [[ "$NODE" != "$TARGET_NODE" ]]; then
        echo "❌ A '$DEPLOYMENT' Pod is on '$NODE', but '$TARGET' runs on '$TARGET_NODE'"
        exit 1
    fi
    COUNT=$((COUNT + 1))
done <<< "$NODES"

if [[ "$COUNT" -lt 2 ]]; then
    echo "❌ Only ${COUNT} running '$DEPLOYMENT' Pod(s) found, expected 2"
    exit 1
fi

echo "✅ All $COUNT '$DEPLOYMENT' replicas share node '$TARGET_NODE' with '$TARGET'"
exit 0
