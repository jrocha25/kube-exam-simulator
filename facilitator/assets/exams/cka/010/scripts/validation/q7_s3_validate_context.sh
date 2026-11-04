#!/bin/bash
set -e

KCFG="/tmp/exam/q7/release.kubeconfig"
CONTEXT="release@lab"

if [[ ! -s "$KCFG" ]]; then
    echo "❌ '$KCFG' is missing or empty"
    exit 1
fi

CURRENT=$(kubectl --kubeconfig="$KCFG" config current-context 2>/dev/null || true)
if [[ "$CURRENT" != "$CONTEXT" ]]; then
    echo "❌ The current context is '${CURRENT:-unset}', expected '$CONTEXT'"
    exit 1
fi

# The context must really be the one in use, not merely named: its user entry
# has to exist, or the file is still broken the way it started.
USER_REF=$(kubectl --kubeconfig="$KCFG" config view -o json 2>/dev/null \
    | jq -r --arg c "$CONTEXT" '.contexts[] | select(.name==$c) | .context.user // empty')
if [[ -z "$USER_REF" ]] || ! kubectl --kubeconfig="$KCFG" config view -o json 2>/dev/null \
        | jq -e --arg u "$USER_REF" '.users[] | select(.name==$u)' >/dev/null; then
    echo "❌ Context '$CONTEXT' refers to user '${USER_REF:-none}', which is not defined in the file"
    exit 1
fi

echo "✅ '$CONTEXT' is the current context and is fully defined"
exit 0
