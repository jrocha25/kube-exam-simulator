#!/bin/bash
set -e

# "No Pods in the namespace" is sampled twice, fifteen seconds apart. A candidate
# who ran "kubectl delete pod" and left the manifest in place has an empty
# namespace for about twenty seconds, and a single sample taken inside that
# window would score the question for the one answer it is designed to reject.

NAMESPACE="node-relay"

if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Namespace '${NAMESPACE}' does not exist; it is part of the lab and should not have been deleted"
    exit 1
fi

count_pods() {
    kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c . || true
}

FIRST=$(count_pods)
if [[ "${FIRST:-0}" -ne 0 ]]; then
    echo "❌ ${FIRST} Pod(s) still in namespace '${NAMESPACE}'"
    exit 1
fi

sleep 15
SECOND=$(count_pods)
if [[ "${SECOND:-0}" -ne 0 ]]; then
    echo "❌ Namespace '${NAMESPACE}' was empty and then ${SECOND} Pod(s) came back"
    echo "   Something on a node is recreating it; deleting the Pod through the API server is not enough."
    exit 1
fi

echo "✅ No Pods in '${NAMESPACE}', and none came back"
exit 0
