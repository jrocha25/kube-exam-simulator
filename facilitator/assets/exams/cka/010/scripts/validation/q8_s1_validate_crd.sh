#!/bin/bash
set -e

CRD="shipments.logistics.ck-x.io"

JSON=$(kubectl get crd "$CRD" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ CustomResourceDefinition '$CRD' not found"
    exit 1
fi

GROUP=$(jq -r '.spec.group' <<<"$JSON")
SCOPE=$(jq -r '.spec.scope' <<<"$JSON")
KIND=$(jq -r '.spec.names.kind' <<<"$JSON")
PLURAL=$(jq -r '.spec.names.plural' <<<"$JSON")
SHORT=$(jq -r '.spec.names.shortNames // [] | join(",")' <<<"$JSON")

[[ "$GROUP" == "logistics.ck-x.io" ]] || { echo "❌ group is '$GROUP', expected logistics.ck-x.io"; exit 1; }
[[ "$SCOPE" == "Namespaced" ]]        || { echo "❌ scope is '$SCOPE', expected Namespaced"; exit 1; }
[[ "$KIND" == "Shipment" ]]           || { echo "❌ kind is '$KIND', expected Shipment"; exit 1; }
[[ "$PLURAL" == "shipments" ]]        || { echo "❌ plural is '$PLURAL', expected shipments"; exit 1; }
grep -qw "shp" <<<"$SHORT"            || { echo "❌ short name 'shp' is missing (found: ${SHORT:-none})"; exit 1; }

VERSIONS=$(jq '.spec.versions | length' <<<"$JSON")
V1=$(jq -r '.spec.versions[] | select(.name=="v1") | "\(.served) \(.storage)"' <<<"$JSON")
if [[ "$VERSIONS" != "1" || "$V1" != "true true" ]]; then
    echo "❌ Expected exactly one version, v1, served and used for storage (found $VERSIONS version(s); v1: ${V1:-absent})"
    exit 1
fi

ESTABLISHED=$(jq -r '.status.conditions[]? | select(.type=="Established") | .status' <<<"$JSON")
if [[ "$ESTABLISHED" != "True" ]]; then
    echo "❌ The CRD is not Established"
    exit 1
fi

echo "✅ CRD '$CRD' exists: Namespaced Shipment/shipments (shp), v1 served and stored"
exit 0
