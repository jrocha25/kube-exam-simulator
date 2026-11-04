#!/bin/bash
set -e

NAMESPACE="crd-freight"
NAME="crate-1042"
CRD="shipments.logistics.ck-x.io"

JSON=$(kubectl get shipments.logistics.ck-x.io "$NAME" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ Shipment '$NAME' not found in namespace '$NAMESPACE'"
    exit 1
fi

DEST=$(jq -r '.spec.destination // empty' <<<"$JSON")
WEIGHT=$(jq -r '.spec.weightKg // empty' <<<"$JSON")
if [[ "$DEST" != "rotterdam" || "$WEIGHT" != "480" ]]; then
    echo "❌ '$NAME' has destination '${DEST:-unset}' and weightKg '${WEIGHT:-unset}', expected rotterdam / 480"
    exit 1
fi

COLUMN=$(kubectl get crd "$CRD" -o json 2>/dev/null \
    | jq -r '.spec.versions[] | select(.name=="v1") | .additionalPrinterColumns[]? | select(.name=="Destination") | .jsonPath // empty')
if [[ "$COLUMN" != ".spec.destination" ]]; then
    echo "❌ No printer column named 'Destination' showing .spec.destination (found jsonPath: ${COLUMN:-none})"
    exit 1
fi

# The short name has to resolve too, or "shp" was only decoration.
if ! kubectl get shp "$NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ 'kubectl get shp $NAME' does not work"
    exit 1
fi

echo "✅ Shipment '$NAME' exists (rotterdam, 480 kg) and the Destination column is defined"
exit 0
