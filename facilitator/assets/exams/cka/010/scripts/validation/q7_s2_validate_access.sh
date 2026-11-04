#!/bin/bash
set -e

KCFG="/tmp/exam/q7/release.kubeconfig"
NAMESPACE="kcfg-release"

if [[ ! -s "$KCFG" ]]; then
    echo "❌ '$KCFG' is missing or empty"
    exit 1
fi

if ! OUT=$(kubectl --kubeconfig="$KCFG" --request-timeout=20s get pods -n "$NAMESPACE" 2>&1 </dev/null); then
    echo "❌ 'kubectl --kubeconfig $KCFG get pods -n $NAMESPACE' fails:"
    head -3 <<<"$OUT" | sed 's/^/   /'
    exit 1
fi

if ! grep -q "release-canary" <<<"$OUT"; then
    echo "❌ The command succeeded but did not list the Pods of '$NAMESPACE'"
    exit 1
fi

echo "✅ Listing Pods in '$NAMESPACE' with the repaired kubeconfig works"
exit 0
