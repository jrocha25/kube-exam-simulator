#!/bin/bash
set -e

# The UID condition is part of this step rather than a cheap constraint check of
# its own: the question forbids deleting and recreating the Pod, and that method
# would otherwise still collect most of the question's marks.
#
# The node is checked Ready first. A Pod on a node whose kubelet has died keeps
# reporting Running for five minutes, so "Running on node02" is only evidence
# once node02 itself is Ready.

NAMESPACE="sched-epicenter"
POD="epicenter-plot"
ALIAS="node02"
UID_FILE="/tmp/exam/q11/pod.uid"

if [[ ! -s "$UID_FILE" ]]; then
    echo "❌ No recorded Pod identity at ${UID_FILE}; the setup for this question did not complete"
    exit 1
fi
EXPECTED_UID=$(tr -d '\r\n' < "$UID_FILE")

NODE=$(awk -F= -v a="$ALIAS" '$1==a {print $2}' /tmp/exam/nodes.env 2>/dev/null | head -1)
if [[ -z "$NODE" ]]; then
    NODE=$(kubectl get nodes -l "ck-x.io/alias=${ALIAS}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
fi
if [[ -z "$NODE" ]]; then
    echo "❌ No node carries the label ck-x.io/alias=${ALIAS}"
    exit 1
fi
if [[ "$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" != "True" ]]; then
    echo "❌ Node '${NODE}' (${ALIAS}) is not Ready, so what runs on it cannot be judged"
    exit 1
fi

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

GOT_UID=$(jq -r '.metadata.uid // ""' <<<"$JSON")
if [[ "$GOT_UID" != "$EXPECTED_UID" ]]; then
    echo "❌ '$POD' is not the Pod the exam started with"
    echo "   Expected UID ${EXPECTED_UID}, found ${GOT_UID:-none}."
    echo "   It was deleted and recreated; the question asked for the existing Pod to end up running."
    exit 1
fi

for _ in $(seq 1 8); do
    PHASE=$(jq -r '.status.phase // ""' <<<"$JSON")
    [[ "$PHASE" == "Running" ]] && break
    sleep 5
    JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)
done

PHASE=$(jq -r '.status.phase // ""' <<<"$JSON")
ON=$(jq -r '.spec.nodeName // ""' <<<"$JSON")

if [[ "$PHASE" != "Running" ]]; then
    echo "❌ '$POD' is ${PHASE:-absent}, expected Running"
    if [[ "$PHASE" == "Pending" ]]; then
        echo "   kubectl describe pod ${POD} -n ${NAMESPACE} reports why the scheduler will not place it."
    fi
    exit 1
fi
if [[ "$ON" != "$NODE" ]]; then
    echo "❌ '$POD' runs on '${ON:-nowhere}', not on '${NODE}' (${ALIAS})"
    exit 1
fi

echo "✅ The original '$POD' Pod is Running on ${ALIAS}"
exit 0
