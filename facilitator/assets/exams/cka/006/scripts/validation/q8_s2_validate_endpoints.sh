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

SERVICE="kube-dns"
NAMESPACE="kube-system"

READY=$(kubectl get endpointslice -n "$NAMESPACE" \
    -l "kubernetes.io/service-name=$SERVICE" -o json 2>/dev/null \
    | jq '[.items[].endpoints[]? | select(.conditions.ready == true)] | length')

if [[ "${READY:-0}" -lt 1 ]]; then
    echo "❌ Service '$SERVICE' has no ready endpoints -- nothing is behind the cluster DNS address"
    exit 1
fi

echo "✅ Service '$SERVICE' has ${READY} ready endpoint(s)"
exit 0
