#!/bin/bash
set -e

NAMESPACE="stor-ledger"
PVC="ledger-data"
STATE_FILE=/tmp/exam/q13/claim

if [[ ! -s "$STATE_FILE" ]]; then
    echo "❌ Setup did not record the claim, so this step cannot be graded"
    exit 1
fi
# The file has no trailing newline, so read reports EOF; the fields are still set.
read -r WANT_UID WANT_VOLUME < "$STATE_FILE" || true

JSON=$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ PersistentVolumeClaim '$PVC' not found in '$NAMESPACE'"
    exit 1
fi

if [[ "$(echo "$JSON" | jq -r '.metadata.uid')" != "$WANT_UID" ]]; then
    echo "❌ '$PVC' was deleted and recreated"
    exit 1
fi
if [[ "$(echo "$JSON" | jq -r '.spec.volumeName')" != "$WANT_VOLUME" ]]; then
    echo "❌ '$PVC' is no longer bound to its original volume"
    exit 1
fi

REQUEST=$(echo "$JSON" | jq -r '.spec.resources.requests.storage')
if [[ "$REQUEST" != "1Gi" ]]; then
    echo "❌ '$PVC' requests $REQUEST, expected 1Gi"
    exit 1
fi

echo "✅ The original '$PVC' requests 1Gi on its original volume"
exit 0
