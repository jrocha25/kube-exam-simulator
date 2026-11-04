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

SELECTOR=$(kubectl get service "$SERVICE" -n "$NAMESPACE" \
    -o jsonpath='{.spec.selector.k8s-app}' 2>/dev/null || true)
if [[ -z "$SELECTOR" ]]; then
    echo "❌ Service '$SERVICE' has no 'k8s-app' selector"
    exit 1
fi

# Rather than hard-coding "kube-dns", read the label the CoreDNS pods actually
# carry. That is the comparison the candidate had to make, and it keeps this
# correct if the cluster's DNS deployment is ever relabelled.
POD_LABEL=$(kubectl get deployment coredns -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.metadata.labels.k8s-app}' 2>/dev/null || true)
if [[ -z "$POD_LABEL" ]]; then
    echo "❌ Could not read the CoreDNS pod template's 'k8s-app' label"
    exit 1
fi

if [[ "$SELECTOR" != "$POD_LABEL" ]]; then
    echo "❌ Service '$SERVICE' selects k8s-app='$SELECTOR' but the CoreDNS Pods carry k8s-app='$POD_LABEL'"
    exit 1
fi

REPLICAS=$(kubectl get deployment coredns -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)
if [[ "${REPLICAS:-0}" -lt 1 ]]; then
    echo "❌ The CoreDNS Deployment has been scaled to ${REPLICAS} -- it was not to be scaled or deleted"
    exit 1
fi

echo "✅ Service '$SERVICE' selects the CoreDNS Pods (k8s-app=$SELECTOR)"
exit 0
