#!/bin/bash
set -e

# Constraint-only step: the snapshot must not have been taken by stopping etcd or
# by restoring over the live datastore. Worth one mark, and it passes on an
# untouched cluster by design.
POD=$(kubectl get pods -n kube-system -l component=etcd \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$POD" ]]; then
    echo "❌ No etcd Pod found in kube-system"
    exit 1
fi

PHASE=$(kubectl get pod "$POD" -n kube-system -o jsonpath='{.status.phase}')
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ etcd Pod '$POD' is '$PHASE', expected 'Running'"
    exit 1
fi

if ! kubectl get nodes >/dev/null 2>&1; then
    echo "❌ The cluster is not answering API requests"
    exit 1
fi

NOT_READY=$(kubectl get nodes -o json | jq -r \
    '[.items[] | select([.status.conditions[] | select(.type=="Ready" and .status=="True")] | length == 0) | .metadata.name] | join(",")')
if [[ -n "$NOT_READY" ]]; then
    echo "❌ These nodes are not Ready: $NOT_READY"
    exit 1
fi

echo "✅ etcd is still running and every node is Ready"
exit 0
