#!/bin/bash

set -e

# Two independent things are asserted, because neither is sufficient alone.
#
#   - The name is exactly "app-settings" with no hash suffix. That is what
#     disableNameSuffixHash buys, and an external consumer reading the object by
#     name is the reason the question asks for it.
#   - configMapGenerator actually appears in the overlay. Without this a
#     hand-written ConfigMap passes the name check trivially. cka/005 q14 could
#     lean on the hash as proof of provenance; with the hash off, that evidence
#     is gone and has to come from the overlay itself.

NAMESPACE="kustom-gen"
CONFIGMAP="app-settings"
OVERLAY="/tmp/exam/q2/overlays/prod"

if ! kubectl get configmap "$CONFIGMAP" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ ConfigMap '$CONFIGMAP' not found in '$NAMESPACE' (a hashed name does not satisfy this)"
    exit 1
fi

REGION=$(kubectl get configmap "$CONFIGMAP" -n "$NAMESPACE" -o jsonpath='{.data.DEPOT_REGION}' 2> /dev/null || true)
if [[ "$REGION" != "north" ]]; then
    echo "❌ ConfigMap key 'DEPOT_REGION' is '${REGION:-unset}', expected 'north'"
    exit 1
fi

MAX=$(kubectl get configmap "$CONFIGMAP" -n "$NAMESPACE" -o jsonpath='{.data.MAX_PARCELS}' 2> /dev/null || true)
if [[ "$MAX" != "5000" ]]; then
    echo "❌ ConfigMap key 'MAX_PARCELS' is '${MAX:-unset}', expected '5000'"
    exit 1
fi

if [[ ! -d "$OVERLAY" ]]; then
    echo "❌ Overlay directory '$OVERLAY' does not exist"
    exit 1
fi

if ! grep -rqs "configMapGenerator" "$OVERLAY"; then
    echo "❌ No configMapGenerator in '$OVERLAY'; the ConfigMap must be generated, not hand-written"
    exit 1
fi

echo "✅ ConfigMap '$CONFIGMAP' is generated with an unsuffixed name and the expected keys"
exit 0
