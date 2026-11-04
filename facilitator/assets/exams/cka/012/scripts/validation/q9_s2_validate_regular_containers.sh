#!/bin/bash
set -e

# The step a mock exam marked wrong. A Pod built with the log collector as a
# native sidecar has ONE regular container, not two, however many containers it
# runs in total -- so the count is the assertion, not just the names.

NAMESPACE="wl-waveform"
POD="waveform-writer"
WANT="ledger-tail,waveform-app"

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

COUNT=$(jq '(.spec.containers // []) | length' <<<"$JSON")
GOT=$(jq -r '[(.spec.containers // [])[].name] | sort | join(",")' <<<"$JSON")

if [[ "$COUNT" != "2" ]]; then
    echo "❌ '$POD' has ${COUNT} regular container(s), expected exactly 2 ('${GOT:-none}')"
    echo "   Containers under initContainers are not regular containers, whether or not they keep running."
    exit 1
fi
if [[ "$GOT" != "$WANT" ]]; then
    echo "❌ '$POD' has regular containers '${GOT}', expected 'waveform-app' and 'ledger-tail'"
    exit 1
fi

echo "✅ '$POD' has exactly two regular containers: waveform-app and ledger-tail"
exit 0
