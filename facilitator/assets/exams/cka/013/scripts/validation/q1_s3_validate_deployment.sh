#!/bin/bash
set -e

# Staged on the auxiliary cluster, so this script drives that one rather than the
# lab's own. Re-exporting KUBECONFIG overrides the caller's for this process only.
export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

# Bounded retry: a control plane that was repaired a moment ago may still be
# coming up, and a candidate who just finished should not lose the question to that.
AUX_UP=no
for _ in 1 2 3 4; do
    kubectl --request-timeout=10s get --raw /readyz >/dev/null 2>&1 && { AUX_UP=yes; break; }
    sleep 10
done
if [[ "$AUX_UP" != yes ]]; then
    echo "❌ The auxiliary API server does not answer"
    exit 1
fi

NAMESPACE="cp-relay"
DEPLOYMENT="relay-hub"
UID_FILE=/tmp/exam/q1/relay-hub.uid

if [[ ! -s "$UID_FILE" ]]; then
    echo "❌ Setup did not record the Deployment's UID, so this step cannot be graded"
    exit 1
fi

DEPLOY_UID=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
if [[ -z "$DEPLOY_UID" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi
if [[ "$DEPLOY_UID" != "$(cat "$UID_FILE")" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' was deleted and recreated"
    exit 1
fi

for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    [[ "$READY" == "2" ]] && break
    sleep 5
done
if [[ "$READY" != "2" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' has ${READY:-0} ready replicas, expected 2"
    exit 1
fi

echo "✅ The original '$DEPLOYMENT' has 2 ready replicas"
exit 0
