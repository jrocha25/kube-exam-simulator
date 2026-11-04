#!/bin/bash
set -e

# Editing the API server's own manifest is the one change in this lab that can
# take the cluster down. This step is worth a single mark and is deliberately
# easy -- it exists so that a hardening change that bricked the cluster does not
# quietly score the same as one that did not.
if ! kubectl get nodes >/dev/null 2>&1; then
    echo "❌ 'kubectl get nodes' fails -- the API server is not serving"
    exit 1
fi

PHASE=$(kubectl get pods -n kube-system -l component=kube-apiserver \
    -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ The kube-apiserver Pod is '${PHASE:-missing}', expected 'Running'"
    exit 1
fi

READY=$(kubectl get pods -n kube-system -l component=kube-apiserver \
    -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || true)
if [[ "$READY" != "true" ]]; then
    echo "❌ The kube-apiserver container is not ready"
    exit 1
fi

echo "✅ The cluster is reachable and kube-apiserver is Running"
exit 0
