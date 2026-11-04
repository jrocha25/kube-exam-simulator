#!/bin/bash

set -e

# A required block alongside the preferences would turn a preference into a
# restriction, which is the shape the question explicitly rules out. Worth 1
# mark: it is a constraint, and it cannot pass before the Deployment exists.

NAMESPACE="sched-prefer"
DEPLOYMENT="tracking-api"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

REQUIRED=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json | jq '
    .spec.template.spec.affinity.nodeAffinity
    .requiredDuringSchedulingIgnoredDuringExecution // null')

if [[ "$REQUIRED" != "null" ]]; then
    echo "❌ '$DEPLOYMENT' also carries a requiredDuringSchedulingIgnoredDuringExecution block"
    echo "   The placement must be a preference only."
    exit 1
fi

echo "✅ '$DEPLOYMENT' expresses a preference only, with no required node affinity"
exit 0
