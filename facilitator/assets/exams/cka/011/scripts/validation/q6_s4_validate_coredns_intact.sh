#!/bin/bash
set -e

# Staged on the auxiliary cluster, so this script drives that one rather than the
# lab's own. The caller exports KUBECONFIG for the primary cluster before every
# validation script; re-exporting here overrides it for this process only.
export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

if [[ -f /tmp/exam/aux-cluster-unavailable ]]; then
    echo "❌ The auxiliary cluster was not available when the lab warmed up, so this question cannot be graded."
    echo "   Rebuild with: ./start.sh --stop && ./start.sh --rebuild"
    exit 1
fi

# Bounded retry: rolling CoreDNS out on a single-node cluster briefly disturbs
# everything that resolves names there, and a candidate who finished a moment
# ago should not lose the question to that.
AUX_UP=no
for _ in 1 2 3 4; do
    kubectl --request-timeout=10s get nodes >/dev/null 2>&1 && { AUX_UP=yes; break; }
    sleep 5
done
if [[ "$AUX_UP" != yes ]]; then
    echo "❌ The auxiliary cluster is unreachable, so this question cannot be graded."
    exit 1
fi

# A constraint check: the question forbids deleting or scaling the CoreDNS
# Deployment, so this passes on an untouched cluster by design and is worth one
# mark. It exists to rule out "fixing" DNS by replacing CoreDNS with something
# else.

if ! kubectl get deployment coredns -n kube-system >/dev/null 2>&1; then
    echo "❌ The CoreDNS Deployment no longer exists on the auxiliary cluster"
    exit 1
fi

DESIRED=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.replicas}' 2>/dev/null || true)
if [[ -z "$DESIRED" || "$DESIRED" -lt 1 ]]; then
    echo "❌ The CoreDNS Deployment is scaled to ${DESIRED:-0} replicas"
    exit 1
fi

for _ in $(seq 1 8); do
    READY=$(kubectl get deployment coredns -n kube-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    [[ "${READY:-0}" -ge "$DESIRED" ]] && break
    sleep 5
done
if [[ "${READY:-0}" -lt "$DESIRED" ]]; then
    echo "❌ CoreDNS has ${READY:-0} of $DESIRED replicas ready -- the Corefile may not parse"
    exit 1
fi

echo "✅ The CoreDNS Deployment is intact and available"
exit 0
