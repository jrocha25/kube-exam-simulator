#!/bin/bash
set -e

LABEL=$(kubectl get namespace edge-team -o jsonpath='{.metadata.labels.gateway-access}' 2>/dev/null || true)
if [[ "$LABEL" != "allowed" ]]; then
    echo "❌ Namespace 'edge-team' carries gateway-access='${LABEL:-<none>}', expected 'allowed'"
    exit 1
fi

echo "✅ Namespace 'edge-team' is labelled gateway-access=allowed"
exit 0
