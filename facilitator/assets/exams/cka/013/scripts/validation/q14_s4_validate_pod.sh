#!/bin/bash
set -e

NAMESPACE="stor-vault"
POD="vault-reader"
STATE_FILE=/tmp/exam/q14/token.sha256
NODE01=$(grep '^node01=' /tmp/exam/nodes.env | cut -d= -f2)

JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json --show-managed-fields 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Pod '$POD' not found in '$NAMESPACE'"
    exit 1
fi

# No placement of its own: no selector, no affinity, and a nodeName written by
# the scheduler's binding (which leaves no managedFields entry) rather than by hand.
if [[ "$(echo "$JSON" | jq '(.spec.nodeSelector // {} | length) + (.spec.affinity // {} | length)')" != "0" ]]; then
    echo "❌ '$POD' carries a nodeSelector or affinity"
    exit 1
fi
if [[ "$(echo "$JSON" | jq '[.metadata.managedFields[]? | select(.fieldsV1."f:spec"."f:nodeName" != null)] | length')" != "0" ]]; then
    echo "❌ '$POD' had its node set by hand"
    exit 1
fi
if [[ "$(echo "$JSON" | jq -r '[.spec.volumes[]? | .persistentVolumeClaim.claimName // empty] | first // empty')" != "vault-claim" ]]; then
    echo "❌ '$POD' does not mount vault-claim"
    exit 1
fi

for _ in $(seq 1 6); do
    PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    [[ "$PHASE" == "Running" ]] && break
    sleep 5
done
NODE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}')
if [[ "$PHASE" != "Running" || "$NODE" != "$NODE01" ]]; then
    echo "❌ '$POD' is '$PHASE' on '${NODE:-no node}'"
    exit 1
fi

SUM=$(kubectl exec -n "$NAMESPACE" "$POD" -- cat /vault/token 2>/dev/null | sha256sum | awk '{print $1}')
if [[ "$SUM" != "$(cat "$STATE_FILE" 2>/dev/null)" ]]; then
    echo "❌ /vault/token inside '$POD' is not the token on the disk"
    exit 1
fi

echo "✅ '$POD' landed on the disk's node through the volume alone and reads the token"
exit 0
