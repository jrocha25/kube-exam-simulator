#!/bin/bash
set -e

SNAPSHOT="/opt/etcd-backup/snapshot.db"
MIN_BYTES=1000000

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes controlplane true >/dev/null 2>&1; then
    echo "❌ Cannot reach the control plane node over SSH"
    exit 1
fi

SIZE=$(ssh controlplane "stat -c %s '$SNAPSHOT' 2>/dev/null" || true)
if [[ -z "$SIZE" ]]; then
    echo "❌ '$SNAPSHOT' does not exist on the control plane node"
    exit 1
fi

if [[ "$SIZE" -lt "$MIN_BYTES" ]]; then
    echo "❌ '$SNAPSHOT' is only ${SIZE} bytes -- too small to be a real etcd snapshot"
    exit 1
fi

# A file of the right size is not proof of a usable backup: ask etcd itself.
if ! ssh controlplane "
    if command -v etcdutl >/dev/null 2>&1; then
        etcdutl snapshot status '$SNAPSHOT' >/dev/null 2>&1
    elif command -v etcdctl >/dev/null 2>&1; then
        ETCDCTL_API=3 etcdctl snapshot status '$SNAPSHOT' >/dev/null 2>&1
    else
        exit 2
    fi
" >/dev/null 2>&1; then
    echo "❌ '$SNAPSHOT' exists but etcd cannot read it as a snapshot"
    exit 1
fi

echo "✅ A valid etcd snapshot of ${SIZE} bytes exists at '$SNAPSHOT'"
exit 0
