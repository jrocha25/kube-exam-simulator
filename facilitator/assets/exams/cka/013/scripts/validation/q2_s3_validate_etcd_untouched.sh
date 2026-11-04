#!/bin/bash
set -e

SNAPSHOT=/opt/etcd-backup/cutover.db
STATE_FILE=/tmp/exam/q2/etcd-container

# A constraint: true of an untouched cluster, so it only counts once the
# snapshot the question asks for exists.
if ! ssh -n -o ConnectTimeout=10 -o BatchMode=yes controlplane "test -s $SNAPSHOT"; then
    echo "❌ No snapshot at $SNAPSHOT yet"
    exit 1
fi

if [[ ! -s "$STATE_FILE" ]]; then
    echo "❌ Setup did not record the etcd container, so this step cannot be graded"
    exit 1
fi

CP=$(grep '^controlplane=' /tmp/exam/nodes.env | cut -d= -f2)
CONTAINER=$(kubectl get pod "etcd-${CP}" -n kube-system -o jsonpath='{.status.containerStatuses[0].containerID}' 2>/dev/null || true)
if [[ "$CONTAINER" != "$(cat "$STATE_FILE")" ]]; then
    echo "❌ The running etcd was restarted or replaced"
    exit 1
fi

if ! ssh -n -o ConnectTimeout=10 -o BatchMode=yes controlplane \
        "grep -q -- '--data-dir=/var/lib/etcd$' /etc/kubernetes/manifests/etcd.yaml"; then
    echo "❌ etcd's manifest no longer serves from /var/lib/etcd"
    exit 1
fi

echo "✅ The running etcd was left alone"
exit 0
