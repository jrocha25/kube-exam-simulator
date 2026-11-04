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
NAMESPACE="kube-system"

# Static Pods have no Deployment to read a version from; each mirror Pod
# carries the image its manifest names, and kubeadm tags every control-plane
# image with the Kubernetes version it belongs to.
for component in kube-apiserver kube-controller-manager kube-scheduler; do
    POD=$(kubectl get pods -n "$NAMESPACE" -l "component=${component},tier=control-plane" -o json 2>/dev/null)
    COUNT=$(jq '.items | length' <<<"$POD")
    if [[ "${COUNT:-0}" -lt 1 ]]; then
        echo "❌ No ${component} Pod found in ${NAMESPACE}"
        exit 1
    fi
    IMAGE=$(jq -r '.items[0].spec.containers[0].image' <<<"$POD")
    PHASE=$(jq -r '.items[0].status.phase' <<<"$POD")
    if [[ "$IMAGE" != *":${TARGET}" ]]; then
        echo "❌ ${component} runs image '${IMAGE}', expected a ${TARGET} image"
        exit 1
    fi
    if [[ "$PHASE" != "Running" ]]; then
        echo "❌ ${component} is ${PHASE}, expected Running"
        exit 1
    fi
done

echo "✅ The API server, controller manager and scheduler run $TARGET"
exit 0
