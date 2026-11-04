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

OUTPUT="/tmp/exam/q8/lookup.txt"

if [[ ! -s "$OUTPUT" ]]; then
    echo "❌ '$OUTPUT' is missing or empty"
    exit 1
fi

if ! grep -q "kubernetes.default.svc.cluster.local" "$OUTPUT"; then
    echo "❌ '$OUTPUT' does not contain a resolved answer for kubernetes.default.svc.cluster.local"
    exit 1
fi

# The lookup had to come from inside the cluster. A resolver that answered from
# the jumphost would not mention the cluster DNS service address.
DNS_IP=$(kubectl get service kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
if [[ -n "$DNS_IP" ]] && ! grep -q "$DNS_IP" "$OUTPUT"; then
    echo "❌ '$OUTPUT' does not name the cluster DNS server ($DNS_IP)."
    echo "   The lookup must be run inside the 'ticker' Pod."
    exit 1
fi

echo "✅ '$OUTPUT' holds an in-cluster lookup of kubernetes.default"
exit 0
