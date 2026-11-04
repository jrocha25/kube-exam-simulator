#!/bin/bash
set -e

# "Do not change the Pod" is a real constraint here, not decoration: relaxing the
# nodeSelector would place the Pod without teaching anything about node labels.
# The fingerprint is re-recorded on every warm-up, and this is guarded on the Pod
# actually running, so it cannot pay out on an untouched cluster.

NAMESPACE="sched-epicenter"
POD="epicenter-plot"
DIR="/tmp/exam/q11"

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

if [[ "$(jq -r '.status.phase // ""' <<<"$JSON")" != "Running" ]]; then
    echo "❌ '$POD' is not Running yet, so there is nothing to confirm"
    exit 1
fi

if [[ ! -s "${DIR}/pod.sha" ]]; then
    echo "❌ No baseline fingerprint at ${DIR}/pod.sha; the setup for this question did not complete"
    exit 1
fi

EXPECTED=$(tr -d '\r\n' < "${DIR}/pod.sha")
# Same exclusion as the baseline: the scheduler writes nodeName, and placing the
# Pod is the whole point of the question.
GOT=$(jq -S '.spec | del(.nodeName)' <<<"$JSON" | sha256sum | awk '{print $1}')

if [[ "$GOT" != "$EXPECTED" ]]; then
    echo "❌ The spec of '$POD' has changed since the exam started"
    SELECTOR=$(jq -r '(.spec.nodeSelector // {}) | to_entries | map("\(.key)=\(.value)") | join(",")' <<<"$JSON")
    echo "   Its nodeSelector is now '${SELECTOR:-none}'."
    echo "   The Pod was to be left alone; the work belonged on the node."
    exit 1
fi

echo "✅ '$POD' is running and its own spec was never modified"
exit 0
