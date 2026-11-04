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

NODE=$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}')

# The kubelet re-registers a few seconds after its restart; give a correct
# answer that was finished moments ago a bounded chance.
for _ in $(seq 1 12); do
    VERSION=$(kubectl get node "$NODE" -o jsonpath='{.status.nodeInfo.kubeletVersion}' 2>/dev/null || true)
    READY=$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$VERSION" == "$TARGET" && "$READY" == "True" ]] && break
    sleep 5
done

if [[ "$VERSION" != "$TARGET" ]]; then
    echo "❌ Node '$NODE' reports kubelet '${VERSION:-unknown}', expected $TARGET"
    exit 1
fi
if [[ "$READY" != "True" ]]; then
    echo "❌ Node '$NODE' is not Ready"
    exit 1
fi

echo "✅ Node '$NODE' is Ready with kubelet $TARGET"
exit 0
