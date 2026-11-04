#!/bin/bash
set -e

NAMESPACE="rbac-deploy"
USER="system:serviceaccount:rbac-deploy:release-bot"

check_denied() {
    local verb="$1" resource="$2"
    local answer
    answer=$(kubectl auth can-i "$verb" "$resource" --as="$USER" -n "$NAMESPACE" 2>/dev/null || true)
    if [[ "$answer" == "yes" ]]; then
        echo "❌ '$USER' can '$verb' '$resource' in '$NAMESPACE'; the grant is too broad"
        exit 1
    fi
}

check_denied update deployments
check_denied patch  deployments
check_denied delete deployments
check_denied create deployments
check_denied delete pods
check_denied get    secrets

echo "✅ 'release-bot' cannot modify the Deployment object itself"
exit 0
