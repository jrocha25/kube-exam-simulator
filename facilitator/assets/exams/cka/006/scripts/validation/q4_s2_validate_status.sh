#!/bin/bash
set -e

STATUS_FILE="/opt/etcd-backup/status.json"

CONTENT=$(ssh -o ConnectTimeout=10 controlplane "cat '$STATUS_FILE' 2>/dev/null" || true)
if [[ -z "$CONTENT" ]]; then
    echo "❌ '$STATUS_FILE' is missing or empty on the control plane node"
    exit 1
fi

if ! jq -e . >/dev/null 2>&1 <<<"$CONTENT"; then
    echo "❌ '$STATUS_FILE' is not valid JSON"
    exit 1
fi

# etcdctl/etcdutl snapshot status --write-out=json emits hash, revision,
# totalKey and totalSize. Accept either the object or a single-element array.
REVISION=$(jq -r 'if type=="array" then .[0] else . end | .revision // empty' <<<"$CONTENT")
TOTALKEY=$(jq -r 'if type=="array" then .[0] else . end | .totalKey // empty' <<<"$CONTENT")

if [[ -z "$REVISION" || -z "$TOTALKEY" ]]; then
    echo "❌ '$STATUS_FILE' is JSON but does not look like an etcd snapshot status"
    echo "   (expected 'revision' and 'totalKey' fields)"
    exit 1
fi

if [[ "$TOTALKEY" -lt 1 ]]; then
    echo "❌ The snapshot status reports $TOTALKEY keys -- the snapshot is empty"
    exit 1
fi

echo "✅ '$STATUS_FILE' holds a JSON snapshot status (revision $REVISION, $TOTALKEY keys)"
exit 0
