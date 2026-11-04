#!/bin/bash
set -e

NAMESPACE="ts-probe"
DEPLOYMENT="frontend"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

restart_total() {
    kubectl get pods -n "$NAMESPACE" -l app=frontend -o json | jq '[.items[].status.containerStatuses // [] | .[].restartCount] | add // 0'
}

ready_total() {
    kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}'
}

BEFORE=$(restart_total)
READY_BEFORE=$(ready_total)

# Fail before the stability window rather than after it. A Deployment that is already
# restarting, or already short of replicas, is not going to be rescued by waiting, and
# this script runs alongside every other check at the end of the exam.
if [[ "$BEFORE" != "0" ]]; then
    echo "❌ frontend Pods are restarting (restart count: $BEFORE)"
    exit 1
fi

if [[ "$READY_BEFORE" != "2" ]]; then
    echo "❌ frontend does not have 2 ready replicas (observed: $READY_BEFORE)"
    exit 1
fi

# Only now is it worth paying for the window that proves the fix held.
sleep 30
AFTER=$(restart_total)
READY_AFTER=$(ready_total)

if [[ "$AFTER" != "0" ]]; then
    echo "❌ frontend Pods are restarting (restart count: $BEFORE then $AFTER)"
    exit 1
fi

if [[ "$READY_AFTER" != "2" ]]; then
    echo "❌ frontend did not stay at 2 ready replicas (observed: $READY_BEFORE then $READY_AFTER)"
    exit 1
fi

echo "✅ frontend Pods stay ready and no longer restart"
exit 0
