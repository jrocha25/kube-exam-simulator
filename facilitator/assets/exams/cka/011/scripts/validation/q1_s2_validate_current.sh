#!/bin/bash
set -e

KCFG="/tmp/exam/q1/ops.kubeconfig"

if [[ ! -s "$KCFG" ]]; then
    echo "❌ '$KCFG' is missing or empty"
    exit 1
fi

CURRENT=$(kubectl --kubeconfig="$KCFG" config current-context 2>/dev/null </dev/null || true)
if [[ "$CURRENT" != "tower" ]]; then
    echo "❌ The current context is '${CURRENT:-none}', expected 'tower'"
    exit 1
fi

# The bootstrap context was to be left alone, not replaced.
BOOT_CLUSTER=$(kubectl --kubeconfig="$KCFG" config view \
    -o jsonpath="{.contexts[?(@.name=='bootstrap')].context.cluster}" 2>/dev/null </dev/null || true)
BOOT_USER=$(kubectl --kubeconfig="$KCFG" config view \
    -o jsonpath="{.contexts[?(@.name=='bootstrap')].context.user}" 2>/dev/null </dev/null || true)
if [[ "$BOOT_CLUSTER" != "airops" || "$BOOT_USER" != "tower-ops" ]]; then
    echo "❌ The 'bootstrap' context is missing or was altered"
    exit 1
fi

echo "✅ 'tower' is the current context and 'bootstrap' is intact"
exit 0
