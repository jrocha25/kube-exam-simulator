#!/bin/bash

set -e

# The discriminating check. Patching the two backends by name produces exactly
# the same result on them as a label-selected target does; only the frontend
# tells the two apart -- and only if the patch was actually scoped.
#
# Guarded on the backends having been patched, so an untouched cluster (where the
# frontend is trivially unpatched) scores nothing here.

NAMESPACE="kustom-patch"
ENV_NAME="SHIFT_WINDOW"

BACKEND_VALUE=$(kubectl get deployment route-planner -n "$NAMESPACE" -o json 2> /dev/null \
    | jq -r --arg n "$ENV_NAME" '[ .spec.template.spec.containers[]?.env[]? | select(.name == $n) | .value ][0] // ""' 2> /dev/null || true)
if [[ "$BACKEND_VALUE" != "night" ]]; then
    echo "❌ The backend Deployments are not patched yet, so this check cannot mean anything"
    exit 1
fi

if ! kubectl get deployment driver-portal -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment 'driver-portal' not found in namespace '$NAMESPACE'"
    exit 1
fi

FRONTEND_VALUE=$(kubectl get deployment driver-portal -n "$NAMESPACE" -o json \
    | jq -r --arg n "$ENV_NAME" '[ .spec.template.spec.containers[]?.env[]? | select(.name == $n) | .value ][0] // ""')
if [[ -n "$FRONTEND_VALUE" ]]; then
    echo "❌ 'driver-portal' also carries ${ENV_NAME}='${FRONTEND_VALUE}'; the patch was not scoped to tier=backend"
    exit 1
fi

echo "✅ 'driver-portal' was left untouched while both backends were patched"
exit 0
