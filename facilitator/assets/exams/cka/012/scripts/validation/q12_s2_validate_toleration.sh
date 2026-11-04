#!/bin/bash
set -e

# This has to match the seeded taint by key and by value, not merely be non-empty:
# every Pod already carries two tolerations that the DefaultTolerationSeconds
# admission plugin adds (not-ready and unreachable, both NoExecute), so
# "spec.tolerations is set" is true of the untouched, Pending Pod.
#
# A catch-all is rejected as the question says: an Exists toleration with no key
# tolerates every taint in the cluster, which is not a fix, it is a blanket.

NAMESPACE="sched-borehole"
POD="borehole-sampler"
TAINT_KEY="seismo.io/borehole"
TAINT_VALUE="restricted"

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

if jq -e '[(.spec.tolerations // [])[] | select((.key // "") == "" and (.operator // "") == "Exists")] | length > 0' <<<"$JSON" >/dev/null; then
    echo "❌ '$POD' carries a catch-all toleration (operator: Exists with no key), which tolerates every taint"
    echo "   The question asks for the key and the value to be matched explicitly."
    exit 1
fi

if ! jq -e --arg k "$TAINT_KEY" --arg v "$TAINT_VALUE" '
    [ (.spec.tolerations // [])[]
      | select(.key == $k)
      | select((.operator // "Equal") == "Equal")
      | select(.value == $v)
      | select((.effect // "NoSchedule") == "NoSchedule")
    ] | length > 0' <<<"$JSON" >/dev/null; then
    GOT=$(jq -r '[(.spec.tolerations // [])[] | "\(.key // "*")\(if .value then "="+.value else "" end):\(.effect // "*")"] | join(" ")' <<<"$JSON")
    echo "❌ '$POD' has no toleration for ${TAINT_KEY}=${TAINT_VALUE} with effect NoSchedule"
    echo "   Its tolerations are: ${GOT:-none}"
    echo "   The two NoExecute entries are added to every Pod automatically and tolerate nothing here."
    exit 1
fi

echo "✅ '$POD' tolerates ${TAINT_KEY}=${TAINT_VALUE}:NoSchedule by key and value"
exit 0
