#!/bin/bash

set -e

# The Service is checked alongside the two Deployments because it comes from the
# app base only. A label transformer reaches every resource the overlay builds,
# from both directories; hand-editing one base reaches only its own.

NAMESPACE="kustom-compose"
LABEL="release"
EXPECTED="winter-2026"

check() {
    local KIND="$1" NAME="$2"
    local VALUE
    VALUE=$(kubectl get "$KIND" "$NAME" -n "$NAMESPACE" \
        -o jsonpath="{.metadata.labels.${LABEL}}" 2> /dev/null || true)
    if [[ "$VALUE" != "$EXPECTED" ]]; then
        echo "❌ ${KIND}/${NAME} has ${LABEL}='${VALUE:-unset}', expected '$EXPECTED'"
        exit 1
    fi
}

check deployment waybill-api
check deployment waybill-cache
check service waybill-api

echo "✅ '${LABEL}=${EXPECTED}' is present on resources originating from both bases"
exit 0
