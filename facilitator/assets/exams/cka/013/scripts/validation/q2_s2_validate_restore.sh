#!/bin/bash
set -e

NAMESPACE="etcd-cutover"
RESTORE_DIR=/opt/etcd-backup/cutover-verify

MARKER_RV=$(kubectl get configmap cutover-marker -n "$NAMESPACE" -o jsonpath='{.metadata.resourceVersion}' 2>/dev/null || true)
if [[ -z "$MARKER_RV" ]]; then
    echo "❌ ConfigMap 'cutover-marker' not found in '$NAMESPACE'"
    exit 1
fi

# A restore writes a whole member directory: the bolt database and a write-ahead
# log. A database file copied into place by hand has no WAL.
if ! ssh -n -o ConnectTimeout=10 -o BatchMode=yes controlplane \
        "test -s $RESTORE_DIR/member/snap/db && ls $RESTORE_DIR/member/wal/*.wal >/dev/null 2>&1"; then
    echo "❌ $RESTORE_DIR on controlplane does not hold a restored etcd member (member/snap/db and member/wal)"
    exit 1
fi

STATUS=$(ssh -n -o ConnectTimeout=10 -o BatchMode=yes controlplane \
    "etcdutl snapshot status $RESTORE_DIR/member/snap/db -w json" 2>/dev/null || true)
REVISION=$(echo "$STATUS" | jq -r '.revision // empty' 2>/dev/null || true)
if [[ -z "$REVISION" ]]; then
    echo "❌ The restored database in $RESTORE_DIR cannot be read"
    exit 1
fi
if (( REVISION < MARKER_RV )); then
    echo "❌ The restored data is at revision $REVISION, older than cutover-marker ($MARKER_RV)"
    exit 1
fi

echo "✅ The snapshot was restored into $RESTORE_DIR (revision $REVISION)"
exit 0
