#!/bin/bash
set -e

# The expected values are read off the node now, not hardcoded: the container ID
# changes on every warm-up, so the file can only be right if the candidate
# actually looked. crictl ps prints a truncated ID, so a prefix match is what a
# correct answer looks like.

NAMESPACE="node-crictl"
POD="tug"
FILE="/tmp/exam/q13/container.txt"

if [[ -f /tmp/exam/node-ssh-unavailable ]]; then
    echo "❌ There is no shell on the cluster nodes, so this question cannot be graded."
    echo "   Rebuild with: ./start.sh --stop && ./start.sh --rebuild"
    exit 1
fi
if [[ ! -s "$FILE" ]]; then
    echo "❌ '$FILE' is missing or empty"
    exit 1
fi

NODE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
if [[ -z "$NODE" ]]; then
    echo "❌ Pod '$POD' is not scheduled, so its container cannot be located"
    exit 1
fi

ALIAS=$(awk -F= -v n="$NODE" '$2==n {print $1}' /tmp/exam/nodes.env 2>/dev/null | head -1)
if [[ -z "$ALIAS" ]]; then
    echo "❌ No SSH alias is known for node '$NODE'"
    exit 1
fi

FULL_ID=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$ALIAS" \
    "crictl ps -q --name '^${POD}\$' --state Running" 2>/dev/null | head -1 | tr -d '\r')
if [[ -z "$FULL_ID" ]]; then
    echo "❌ No running container named '${POD}' was found on node '${NODE}'"
    exit 1
fi

EXPECTED_RUNTIME=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$ALIAS" \
    "crictl inspect ${FULL_ID}" 2>/dev/null | jq -r '.info.runtimeType // empty' | head -1 | tr -d '\r')
if [[ -z "$EXPECTED_RUNTIME" ]]; then
    echo "❌ Could not read the runtimeType of that container from node '${NODE}'"
    exit 1
fi

GOT_ID=$(awk 'NF {print $1; exit}' "$FILE" | tr -d '\r')
GOT_RUNTIME=$(awk 'NF {print $2; exit}' "$FILE" | tr -d '\r')

if [[ -z "$GOT_ID" || -z "$GOT_RUNTIME" ]]; then
    echo "❌ '$FILE' does not hold a container ID and a runtime type separated by a space"
    exit 1
fi
if [[ "${#GOT_ID}" -lt 8 ]]; then
    echo "❌ '${GOT_ID}' is too short to be a container ID"
    exit 1
fi
if [[ "${FULL_ID}" != "${GOT_ID}"* ]]; then
    echo "❌ '${GOT_ID}' is not the ID of the container running '${POD}' on node '${NODE}'"
    exit 1
fi
if [[ "$GOT_RUNTIME" != "$EXPECTED_RUNTIME" ]]; then
    echo "❌ '$FILE' reports runtime type '${GOT_RUNTIME}', the node reports '${EXPECTED_RUNTIME}'"
    exit 1
fi

echo "✅ '$FILE' names the running container and its runtime type"
exit 0
