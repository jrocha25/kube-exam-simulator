#!/bin/bash
set -e

# Stopping or masking the kubelet also stops the Pod coming back, and it is the
# wrong answer: it takes the node with it. Guarded on the manifest being gone so
# that it cannot pay out on an untouched cluster, and both facts are read in one
# ssh call.

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
HITS=$(grep -rls -- "$POD_BASE" "$DIR" /etc/kubernetes/manifests 2>/dev/null | sort -u | tr '\n' ' ')
echo "HITS=${HITS}"
echo "STATE=$(systemctl is-active kubelet 2>/dev/null)"
echo "ENABLED=$(systemctl is-enabled kubelet 2>/dev/null)"
REMOTE
) || true

HITS=$(sed -n 's/^HITS=//p' <<<"$OUT" | head -1)
STATE=$(sed -n 's/^STATE=//p' <<<"$OUT" | head -1)
ENABLED=$(sed -n 's/^ENABLED=//p' <<<"$OUT" | head -1)

if [[ -z "$STATE" ]]; then
    echo "❌ Could not ask ${TARGET} about its kubelet"
    exit 1
fi

if [[ -n "${HITS// /}" ]]; then
    echo "❌ The manifest for '${POD_BASE}' is still on ${TARGET}, so there is nothing to confirm yet"
    exit 1
fi

if [[ "$STATE" != "active" ]]; then
    echo "❌ The kubelet on ${TARGET} is '${STATE}', not 'active'"
    echo "   Stopping the kubelet does stop the Pod coming back, and takes the node with it."
    exit 1
fi

if [[ "$ENABLED" == "masked" ]]; then
    echo "❌ The kubelet unit on ${TARGET} is masked"
    exit 1
fi

echo "✅ The kubelet on ${TARGET} is still active, and the manifest is gone"
exit 0
