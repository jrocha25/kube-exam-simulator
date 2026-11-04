#!/bin/bash
set -e

NAMESPACE="etcd-cutover"
SNAPSHOT=/opt/etcd-backup/cutover.db

WAVE=$(kubectl get configmap cutover-marker -n "$NAMESPACE" -o jsonpath='{.data.wave}' 2>/dev/null || true)
if [[ "$WAVE" != "harbour-7" ]]; then
    echo "❌ ConfigMap 'cutover-marker' with wave=harbour-7 not found in '$NAMESPACE'"
    exit 1
fi
MARKER_RV=$(kubectl get configmap cutover-marker -n "$NAMESPACE" -o jsonpath='{.metadata.resourceVersion}')

STATUS=$(ssh -n -o ConnectTimeout=10 -o BatchMode=yes controlplane \
    "test -s $SNAPSHOT && etcdutl snapshot status $SNAPSHOT -w json" 2>/dev/null || true)
REVISION=$(echo "$STATUS" | jq -r '.revision // empty' 2>/dev/null || true)
if [[ -z "$REVISION" ]]; then
    echo "❌ $SNAPSHOT on controlplane is missing or is not a valid etcd snapshot"
    exit 1
fi

# A ConfigMap's resourceVersion is the etcd revision that wrote it, so a
# snapshot that contains the marker has a revision at least that high.
if (( REVISION < MARKER_RV )); then
    echo "❌ The snapshot (revision $REVISION) was taken before cutover-marker was created (revision $MARKER_RV)"
    exit 1
fi

echo "✅ $SNAPSHOT is a valid snapshot at revision $REVISION, which includes cutover-marker"
exit 0
