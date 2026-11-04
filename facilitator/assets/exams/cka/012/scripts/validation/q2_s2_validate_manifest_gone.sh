#!/bin/bash
set -e

# The manifest is looked for in the directory node01's kubelet reads, and in the
# kubeadm default as well, so that moving the file rather than deleting it does
# not pass. One ssh call.

POD_BASE="relay-shim"
TARGET="node01"

if [[ -f /tmp/exam/node-ssh-unavailable ]]; then
    echo "❌ There is no shell on the cluster nodes, so this question cannot be graded."
    echo "   Rebuild with: ./start.sh --stop && ./start.sh --rebuild"
    exit 1
fi

OUT=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$TARGET" "POD_BASE=${POD_BASE} bash -s" 2>/dev/null <<'REMOTE' | tr -d '\r'
CFG=/var/lib/kubelet/config.yaml
DIR=$(awk '/^staticPodPath:/ {print $2}' "$CFG" 2>/dev/null)
[ -n "$DIR" ] || DIR=/etc/kubernetes/manifests
echo "DIR=${DIR}"
HITS=$(grep -rls -- "$POD_BASE" "$DIR" /etc/kubernetes/manifests 2>/dev/null | sort -u | tr '\n' ' ')
echo "HITS=${HITS}"
REMOTE
) || true

DIR=$(sed -n 's/^DIR=//p' <<<"$OUT" | head -1)
HITS=$(sed -n 's/^HITS=//p' <<<"$OUT" | head -1)

if [[ -z "$DIR" ]]; then
    echo "❌ Could not read the kubelet configuration on ${TARGET}"
    exit 1
fi

if [[ -n "${HITS// /}" ]]; then
    echo "❌ A manifest for '${POD_BASE}' is still on ${TARGET}: ${HITS}"
    echo "   Its kubelet reads '${DIR}'."
    exit 1
fi

echo "✅ No manifest for '${POD_BASE}' on ${TARGET} any more"
exit 0
