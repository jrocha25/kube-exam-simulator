#!/bin/bash
set -e

NAMESPACE="rbac-deploy"
DEPLOYMENT="storefront"
USER="system:serviceaccount:rbac-deploy:release-bot"

# "can-i patch deployments/scale" is read as "the Deployment named scale"; the
# subresource has to be named with --subresource.
check_allowed() {
    local verb="$1"
    local answer
    answer=$(kubectl auth can-i "$verb" deployments --subresource=scale --as="$USER" -n "$NAMESPACE" 2>/dev/null || true)
    if [[ "$answer" != "yes" ]]; then
        echo "❌ '$USER' cannot '$verb' the scale subresource of Deployments in '$NAMESPACE'"
        exit 1
    fi
}

check_allowed get
check_allowed patch
check_allowed update

READ=$(kubectl auth can-i list deployments --as="$USER" -n "$NAMESPACE" 2>/dev/null || true)
if [[ "$READ" != "yes" ]]; then
    echo "❌ '$USER' cannot list Deployments in '$NAMESPACE'"
    exit 1
fi

# Prove it end to end: the account must actually be able to scale.
if ! kubectl scale deployment "$DEPLOYMENT" -n "$NAMESPACE" --replicas=2 --as="$USER" &> /dev/null; then
    echo "❌ '$USER' could not scale Deployment '$DEPLOYMENT' in '$NAMESPACE'"
    exit 1
fi

echo "✅ 'release-bot' can read Deployments and scale them through the scale subresource"
exit 0
