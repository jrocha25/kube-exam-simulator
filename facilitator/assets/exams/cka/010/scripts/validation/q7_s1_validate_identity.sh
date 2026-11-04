#!/bin/bash
set -e

KCFG="/tmp/exam/q7/release.kubeconfig"
EXPECTED="system:serviceaccount:kcfg-release:release-bot"

# Every kubectl below gets </dev/null. A context whose user entry has no
# credentials makes kubectl *prompt for a username* on stdin, and the exec
# session the facilitator runs this in never closes stdin -- so without the
# redirect an unsolved attempt hangs to the 90s cap instead of failing.

if [[ ! -s "$KCFG" ]]; then
    echo "❌ '$KCFG' is missing or empty"
    exit 1
fi

WHO=$(kubectl --kubeconfig="$KCFG" --request-timeout=20s auth whoami -o json 2>/dev/null </dev/null \
    | jq -r '.status.userInfo.username // empty' || true)
if [[ -z "$WHO" ]]; then
    echo "❌ '$KCFG' cannot authenticate against the cluster"
    kubectl --kubeconfig="$KCFG" --request-timeout=20s auth whoami 2>&1 </dev/null | head -3 | sed 's/^/   /'
    exit 1
fi
if [[ "$WHO" != "$EXPECTED" ]]; then
    echo "❌ '$KCFG' authenticates as '$WHO', expected '$EXPECTED'"
    exit 1
fi

echo "✅ '$KCFG' authenticates as $EXPECTED"
exit 0
