#!/bin/bash
set -e

KCFG="/tmp/exam/q1/ops.kubeconfig"
CONTEXT="tower"
CLUSTER="airops"
USER_NAME="tower-ops"
NAMESPACE="ops-access"

if [[ ! -s "$KCFG" ]]; then
    echo "❌ '$KCFG' is missing or empty"
    exit 1
fi

read_field() {
    kubectl --kubeconfig="$KCFG" config view \
        -o jsonpath="{.contexts[?(@.name=='${CONTEXT}')].context.$1}" 2>/dev/null </dev/null || true
}

GOT_CLUSTER=$(read_field cluster)
GOT_USER=$(read_field user)
GOT_NAMESPACE=$(read_field namespace)

if [[ -z "$GOT_CLUSTER$GOT_USER$GOT_NAMESPACE" ]]; then
    echo "❌ '$KCFG' has no context named '$CONTEXT'"
    exit 1
fi
if [[ "$GOT_CLUSTER" != "$CLUSTER" ]]; then
    echo "❌ Context '$CONTEXT' uses cluster '${GOT_CLUSTER:-none}', expected '$CLUSTER'"
    exit 1
fi
if [[ "$GOT_USER" != "$USER_NAME" ]]; then
    echo "❌ Context '$CONTEXT' uses user '${GOT_USER:-none}', expected '$USER_NAME'"
    exit 1
fi
if [[ "$GOT_NAMESPACE" != "$NAMESPACE" ]]; then
    echo "❌ Context '$CONTEXT' selects namespace '${GOT_NAMESPACE:-none}', expected '$NAMESPACE'"
    exit 1
fi

echo "✅ Context '$CONTEXT' binds ${CLUSTER}/${USER_NAME} with the '${NAMESPACE}' namespace"
exit 0
