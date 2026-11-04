#!/bin/bash
set -e

# emptyDir specifically: a hostPath or a PVC would also let the three containers
# share a path, and would not be the Pod-scoped scratch space the question is about.

NAMESPACE="wl-waveform"
POD="waveform-writer"
VOLUME="ledger"

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

if ! jq -e --arg v "$VOLUME" '[(.spec.volumes // [])[] | select(.name == $v)] | length == 1' <<<"$JSON" >/dev/null; then
    NAMES=$(jq -r '[(.spec.volumes // [])[].name] | join(",")' <<<"$JSON")
    echo "❌ '$POD' has no volume named '${VOLUME}' (found '${NAMES:-none}')"
    exit 1
fi

if ! jq -e --arg v "$VOLUME" '[(.spec.volumes // [])[] | select(.name == $v) | select(.emptyDir != null)] | length == 1' <<<"$JSON" >/dev/null; then
    KIND=$(jq -r --arg v "$VOLUME" '[(.spec.volumes // [])[] | select(.name == $v)][0] | del(.name) | keys[0] // "unknown"' <<<"$JSON")
    echo "❌ Volume '${VOLUME}' is a '${KIND}', expected an emptyDir"
    exit 1
fi

echo "✅ Volume '${VOLUME}' is an emptyDir"
exit 0
