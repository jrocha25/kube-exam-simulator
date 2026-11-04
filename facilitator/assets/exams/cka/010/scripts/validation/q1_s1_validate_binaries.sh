#!/bin/bash
set -e

# Staged on the auxiliary cluster, so this script drives that one rather than the
# lab's own. The caller exports KUBECONFIG for the primary cluster before every
# validation script; re-exporting here overrides it for this process only.
export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

# Bounded retry: a kubelet restart on that node -- part of both questions set
# there -- takes its API server down for half a minute, and a candidate who
# finished a moment ago should not lose the question to that.
AUX_UP=no
for _ in 1 2 3 4; do
    kubectl --request-timeout=10s get nodes >/dev/null 2>&1 && { AUX_UP=yes; break; }
    sleep 5
done
if [[ "$AUX_UP" != yes ]]; then
    echo "❌ The auxiliary cluster is unreachable, so this question cannot be graded."
    echo "   Rebuild with: ./start.sh --stop && ./start.sh --rebuild"
    exit 1
fi

TARGET="v1.34.10"

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes aux true >/dev/null 2>&1; then
    echo "❌ Cannot reach the auxiliary cluster node over SSH"
    exit 1
fi

KUBEADM=$(ssh -o ConnectTimeout=10 aux "kubeadm version -o short" 2>/dev/null || true)
if [[ "$KUBEADM" != "$TARGET" ]]; then
    echo "❌ kubeadm on the aux node reports '${KUBEADM:-nothing}', expected $TARGET"
    exit 1
fi

KUBECTL=$(ssh -o ConnectTimeout=10 aux "kubectl version --client -o json 2>/dev/null" \
    | jq -r '.clientVersion.gitVersion // empty' 2>/dev/null || true)
if [[ "$KUBECTL" != "$TARGET" ]]; then
    echo "❌ kubectl on the aux node reports '${KUBECTL:-nothing}', expected $TARGET"
    exit 1
fi

echo "✅ kubeadm and kubectl on the aux node are $TARGET"
exit 0
