#!/bin/bash
set -e

# Compared against what the node returns right now. nginx's entrypoint writes
# several lines on start, so there is real output to match -- a sleeping busybox
# would log nothing and this check could never fail.

NAMESPACE="node-crictl"
POD="tug"
FILE="/tmp/exam/q13/container.log"

if [[ -f /tmp/exam/node-ssh-unavailable ]]; then
    echo "❌ There is no shell on the cluster nodes, so this question cannot be graded."
    exit 1
fi
if [[ ! -s "$FILE" ]]; then
    echo "❌ '$FILE' is missing or empty"
    exit 1
fi

NODE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)
ALIAS=$(awk -F= -v n="$NODE" '$2==n {print $1}' /tmp/exam/nodes.env 2>/dev/null | head -1)
if [[ -z "$ALIAS" ]]; then
    echo "❌ No SSH alias is known for the node running '$POD'"
    exit 1
fi

FULL_ID=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$ALIAS" \
    "crictl ps -q --name '^${POD}\$' --state Running" 2>/dev/null | head -1 | tr -d '\r')
if [[ -z "$FULL_ID" ]]; then
    echo "❌ No running container named '${POD}' was found on node '${NODE}'"
    exit 1
fi

LIVE=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$ALIAS" "crictl logs ${FULL_ID} 2>&1" 2>/dev/null | tr -d '\r')
if [[ -z "$LIVE" ]]; then
    echo "❌ The container on '${NODE}' produced no logs, so this cannot be graded"
    exit 1
fi

MISSING=0
while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    grep -qF -- "$line" "$FILE" || MISSING=$((MISSING + 1))
done < <(printf '%s\n' "$LIVE" | head -3)

if [[ "$MISSING" -gt 0 ]]; then
    echo "❌ '$FILE' does not match the logs the container is producing on '${NODE}'"
    echo "   ${MISSING} of the first 3 log lines are absent from the file."
    exit 1
fi

echo "✅ '$FILE' holds that container's logs"
exit 0
