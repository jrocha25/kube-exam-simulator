#!/bin/bash
set -e

# A constraint check, so it is guarded on the work actually having been done:
# "the control plane is intact and every node is Ready" is true before the
# candidate starts, and would otherwise be a mark handed over for nothing.

POD_BASE="relay-shim"
TARGET="node01"
COMPONENTS="kube-apiserver etcd kube-controller-manager kube-scheduler"

if [[ -f /tmp/exam/node-ssh-unavailable ]]; then
    echo "❌ There is no shell on the cluster nodes, so this question cannot be graded."
    echo "   Rebuild with: ./start.sh --stop && ./start.sh --rebuild"
    exit 1
fi

HITS=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$TARGET" "POD_BASE=${POD_BASE} bash -s" 2>/dev/null <<'REMOTE' | tr -d '\r'
CFG=/var/lib/kubelet/config.yaml
DIR=$(awk '/^staticPodPath:/ {print $2}' "$CFG" 2>/dev/null)
[ -n "$DIR" ] || DIR=/etc/kubernetes/manifests
grep -rls -- "$POD_BASE" "$DIR" /etc/kubernetes/manifests 2>/dev/null | sort -u | tr '\n' ' '
REMOTE
) || true

if [[ -n "${HITS// /}" ]]; then
    echo "❌ The manifest for '${POD_BASE}' is still on ${TARGET}, so there is nothing to confirm yet"
    exit 1
fi

CONTROLPLANE=$(awk -F= '$1=="controlplane" {print $2}' /tmp/exam/nodes.env 2>/dev/null | head -1)
if [[ -z "$CONTROLPLANE" ]]; then
    echo "❌ The control plane node's name is not known"
    exit 1
fi

for component in $COMPONENTS; do
    if ! kubectl get pod "${component}-${CONTROLPLANE}" -n kube-system >/dev/null 2>&1; then
        echo "❌ The control plane static Pod '${component}-${CONTROLPLANE}' is gone"
        echo "   Only the manifest of the Pod the question is about should have been removed."
        exit 1
    fi
done

NOT_READY=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2 != "Ready" {print $1}' | tr '\n' ' ' || true)
if [[ -n "${NOT_READY// /}" ]]; then
    echo "❌ These nodes are not Ready: ${NOT_READY}"
    exit 1
fi

echo "✅ The control plane static Pods are intact and every node is Ready"
exit 0
