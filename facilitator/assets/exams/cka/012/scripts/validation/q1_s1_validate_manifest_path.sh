#!/bin/bash
set -e

# The manifest has to be in the directory node02's kubelet really reads, which
# this lab's setup has moved away from the kubeadm default. The path is read off
# the node here rather than hardcoded, for the same reason the question asks the
# candidate to read it: whatever the node says is the answer.
#
# One ssh call, not one per check. Twelve retries of a 10-second connect timeout
# would be 120 seconds, over the 90-second script cap.

POD_BASE="sensor-collector"
TARGET="node02"

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
if grep -rlsq -- "$POD_BASE" "$DIR" 2>/dev/null; then echo "FOUND=yes"; else echo "FOUND=no"; fi
if [ "$DIR" != /etc/kubernetes/manifests ] && grep -rlsq -- "$POD_BASE" /etc/kubernetes/manifests 2>/dev/null; then
    echo "STRAY=yes"
else
    echo "STRAY=no"
fi
REMOTE
) || true

DIR=$(sed -n 's/^DIR=//p' <<<"$OUT" | head -1)
FOUND=$(sed -n 's/^FOUND=//p' <<<"$OUT" | head -1)
STRAY=$(sed -n 's/^STRAY=//p' <<<"$OUT" | head -1)

if [[ -z "$DIR" ]]; then
    echo "❌ Could not read the kubelet configuration on ${TARGET}"
    exit 1
fi

if [[ "$FOUND" != "yes" ]]; then
    echo "❌ No manifest for '$POD_BASE' in '${DIR}' on ${TARGET}, which is where that node's kubelet reads static Pod manifests from"
    if [[ "$STRAY" == "yes" ]]; then
        echo "   There is one in /etc/kubernetes/manifests on that node, which its kubelet does not read."
        echo "   The path is staticPodPath in /var/lib/kubelet/config.yaml."
    fi
    exit 1
fi

echo "✅ The manifest for '$POD_BASE' is in '${DIR}' on ${TARGET}"
exit 0
