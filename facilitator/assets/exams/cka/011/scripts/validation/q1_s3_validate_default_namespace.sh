#!/bin/bash
set -e

# Runs kubectl with the candidate's kubeconfig and no -n, so the answer's
# default namespace is what decides the result.
#
# stdin is closed deliberately: a context naming a user entry that does not
# exist makes kubectl prompt for a username, and the facilitator's exec session
# never closes stdin, so the script would hang to the timeout instead of failing.

KCFG="/tmp/exam/q1/ops.kubeconfig"
POD="windsock"

if [[ ! -s "$KCFG" ]]; then
    echo "❌ '$KCFG' is missing or empty"
    exit 1
fi

OUT=$(kubectl --kubeconfig="$KCFG" --request-timeout=20s get pods -o name 2>&1 </dev/null || true)
if ! grep -q "pod/${POD}" <<<"$OUT"; then
    echo "❌ 'kubectl --kubeconfig $KCFG get pods' does not list the '${POD}' Pod of the ops-access namespace"
    echo "   Output: $(head -c 300 <<<"$OUT" | tr '\n' ' ')"
    exit 1
fi

echo "✅ The kubeconfig resolves to the 'ops-access' namespace by default"
exit 0
