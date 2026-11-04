#!/bin/bash
set -e

# Question 8 is staged on the auxiliary cluster, so this script drives that one
# rather than the lab's own. The caller exports KUBECONFIG for the primary cluster
# before every validation script; re-exporting here overrides it for this process
# only, which is why no facilitator change was needed to grade a second cluster.
export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

if ! kubectl --request-timeout=20s get nodes >/dev/null 2>&1; then
    echo "❌ The auxiliary cluster is unreachable, so question 8 cannot be graded."
    echo "   Rebuild with: ./start.sh --stop && ./start.sh --rebuild"
    exit 1
fi

NAMESPACE="dns-check"
POD="ticker"

if ! kubectl get pod "$POD" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ The '$POD' Pod is missing from namespace '$NAMESPACE'"
    exit 1
fi

# Resolution can lag the endpoint appearing by a few seconds while kube-proxy
# reprograms; give it a bounded chance rather than failing a correct answer.
for attempt in 1 2 3 4 5 6; do
    # The fully qualified name, not the short one. busybox's nslookup queries the
    # name exactly as given and never applies the search list from
    # /etc/resolv.conf, so "kubernetes.default" is NXDOMAIN from this Pod even
    # when cluster DNS is perfectly healthy.
    OUT=$(kubectl exec -n "$NAMESPACE" "$POD" -- \
        nslookup kubernetes.default.svc.cluster.local 2>&1 || true)
    if grep -q "kubernetes.default.svc.cluster.local" <<<"$OUT"; then
        echo "✅ '$POD' resolves kubernetes.default.svc.cluster.local"
        exit 0
    fi
    sleep 5
done

echo "❌ '$POD' still cannot resolve kubernetes.default.svc.cluster.local"
echo "   Last output: $(head -c 300 <<<"$OUT")"
exit 1
