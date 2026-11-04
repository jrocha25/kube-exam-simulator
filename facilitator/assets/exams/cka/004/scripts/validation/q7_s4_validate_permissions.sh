#!/bin/bash
set -e

USER="system:serviceaccount:delivery:pipeline-bot"

ALLOWED=$(kubectl auth can-i create deployments.apps --as="$USER" -n delivery 2>/dev/null || true)
if [[ "$ALLOWED" != "yes" ]]; then
    echo "❌ '$USER' cannot create deployments in the 'delivery' namespace"
    exit 1
fi

DENIED=$(kubectl auth can-i create deployments.apps --as="$USER" -n delivery-staging 2>/dev/null || true)
if [[ "$DENIED" == "yes" ]]; then
    echo "❌ '$USER' can create deployments in 'delivery-staging'; the grant must be scoped to 'delivery'"
    exit 1
fi

echo "✅ The permissions of '$USER' are scoped to the 'delivery' namespace"
exit 0
