#!/bin/bash
set -e

# Relabelling the Deployment's Pods, or its own labels, is a much easier way to
# give the Service endpoints -- and it is the one thing the question forbids,
# because the Deployment belongs to someone else. The fingerprint is re-recorded
# on every warm-up, so a candidate who edited it last time has to leave it alone
# again this time.
#
# Guarded on the Service actually working, so that "the Deployment is untouched"
# is not a mark for doing nothing at all.

NAMESPACE="svc-catalog"
DEPLOYMENT="station-catalog"
SERVICE="station-catalog-svc"
DIR="/tmp/exam/q7"
WANT=3

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

READY=$(kubectl get endpointslice -n "$NAMESPACE" -l "kubernetes.io/service-name=${SERVICE}" -o json 2>/dev/null \
    | jq '[.items[].endpoints[]? | select(.conditions.ready == true)] | length' 2>/dev/null || true)
if [[ "${READY:-0}" -ne "$WANT" ]]; then
    echo "❌ '$SERVICE' does not have its ${WANT} ready endpoints yet, so there is nothing to confirm"
    exit 1
fi

if [[ ! -s "${DIR}/deployment.sha" ]]; then
    echo "❌ No baseline fingerprint at ${DIR}/deployment.sha; the setup for this question did not complete"
    exit 1
fi

EXPECTED=$(tr -d '\r\n' < "${DIR}/deployment.sha")
GOT=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq -S '.spec' | sha256sum | awk '{print $1}')

if [[ "$GOT" != "$EXPECTED" ]]; then
    echo "❌ The spec of Deployment '$DEPLOYMENT' has changed since the exam started"
    GEN_BASE=$(tr -d '\r\n' < "${DIR}/deployment.generation" 2>/dev/null || true)
    GEN_NOW=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.metadata.generation}' 2>/dev/null || true)
    echo "   Generation was '${GEN_BASE:-unknown}', now '${GEN_NOW:-unknown}'."
    echo "   The repair was supposed to be entirely on the Service."
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT' is unchanged, and the Service reaches it anyway"
exit 0
