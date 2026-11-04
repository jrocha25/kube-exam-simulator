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

NAMESPACE="etcd-restore"
EXPECTED_FILE="/tmp/exam/q3/ledger-id"

if [[ ! -s "$EXPECTED_FILE" ]]; then
    echo "❌ Setup did not record the original ledger-id, so this step cannot be graded"
    exit 1
fi
EXPECTED=$(cat "$EXPECTED_FILE")

# The API server serves a restore from its watch cache until it is restarted,
# so a candidate who finished a moment ago may still be waiting on that.
for _ in $(seq 1 6); do
    LEDGER_ID=$(kubectl get configmap ledger-state -n "$NAMESPACE" -o jsonpath='{.data.ledger-id}' 2>/dev/null || true)
    [[ "$LEDGER_ID" == "$EXPECTED" ]] && break
    sleep 5
done

if [[ -z "$LEDGER_ID" ]]; then
    echo "❌ ConfigMap 'ledger-state' is missing from namespace '$NAMESPACE'"
    exit 1
fi
if [[ "$LEDGER_ID" != "$EXPECTED" ]]; then
    echo "❌ ConfigMap 'ledger-state' exists but does not carry its original ledger-id"
    exit 1
fi

if kubectl get configmap migration-scratch -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ ConfigMap 'migration-scratch' still exists -- the cluster was not rolled back to the snapshot"
    exit 1
fi

echo "✅ 'ledger-state' is back with its original contents and 'migration-scratch' is gone"
exit 0
