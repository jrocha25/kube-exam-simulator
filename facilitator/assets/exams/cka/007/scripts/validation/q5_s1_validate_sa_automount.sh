#!/bin/bash
set -e

NAMESPACE="rbac-token"
SA="job-runner"

if ! kubectl get serviceaccount "$SA" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ ServiceAccount '$SA' not found in namespace '$NAMESPACE'"
    exit 1
fi

AUTOMOUNT=$(kubectl get serviceaccount "$SA" -n "$NAMESPACE" -o jsonpath='{.automountServiceAccountToken}')
if [[ "$AUTOMOUNT" != "false" ]]; then
    echo "❌ ServiceAccount '$SA' has automountServiceAccountToken '${AUTOMOUNT:-<unset>}', expected 'false'"
    exit 1
fi

echo "✅ ServiceAccount '$SA' does not hand its token to Pods by default"
exit 0
