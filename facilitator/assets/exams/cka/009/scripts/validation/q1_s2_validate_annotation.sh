#!/bin/bash

set -e

# Both resources are checked on purpose. commonAnnotations is a transformer: it
# reaches every resource the overlay builds. A candidate who annotated the
# Deployment by hand instead gets one of the two and fails here, which is the
# whole reason the base ships a Service.

NAMESPACE="kustom-intro"
DEPLOYMENT="parcel-index-dev"
SERVICE="parcel-index-dev"
ANNOTATION="owner"
EXPECTED="platform-team"

DEPLOY_VALUE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
    -o jsonpath="{.metadata.annotations.${ANNOTATION}}" 2> /dev/null || true)
if [[ "$DEPLOY_VALUE" != "$EXPECTED" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' annotation '$ANNOTATION' is '${DEPLOY_VALUE:-unset}', expected '$EXPECTED'"
    exit 1
fi

SERVICE_VALUE=$(kubectl get service "$SERVICE" -n "$NAMESPACE" \
    -o jsonpath="{.metadata.annotations.${ANNOTATION}}" 2> /dev/null || true)
if [[ "$SERVICE_VALUE" != "$EXPECTED" ]]; then
    echo "❌ Service '$SERVICE' annotation '$ANNOTATION' is '${SERVICE_VALUE:-unset}', expected '$EXPECTED'"
    exit 1
fi

echo "✅ '$ANNOTATION=$EXPECTED' is present on both the Deployment and the Service"
exit 0
