#!/bin/bash
set -e

NAMESPACE="crd-freight"

if ! kubectl get crd shipments.logistics.ck-x.io >/dev/null 2>&1; then
    echo "❌ CustomResourceDefinition 'shipments.logistics.ck-x.io' not found"
    exit 1
fi

# --dry-run=server runs the API server's validation without persisting
# anything, which is the honest way to prove a schema rejects what it should.
try() {
    kubectl create --dry-run=server -f - >/dev/null 2>&1 <<YAML
apiVersion: logistics.ck-x.io/v1
kind: Shipment
metadata:
  name: probe
  namespace: $NAMESPACE
spec:
$1
YAML
}

if try "  destination: hamburg
  weightKg: 0"; then
    echo "❌ A Shipment with weightKg 0 was accepted -- the minimum of 1 is not enforced"
    exit 1
fi
if try "  weightKg: 12"; then
    echo "❌ A Shipment without spec.destination was accepted -- it is not required"
    exit 1
fi
if try "  destination: hamburg"; then
    echo "❌ A Shipment without spec.weightKg was accepted -- it is not required"
    exit 1
fi
if try "  destination: hamburg
  weightKg: twelve"; then
    echo "❌ A Shipment with a non-integer weightKg was accepted"
    exit 1
fi
if ! try "  destination: hamburg
  weightKg: 12"; then
    echo "❌ A valid Shipment (destination hamburg, weightKg 12) was rejected"
    exit 1
fi

echo "✅ The schema rejects invalid Shipments and accepts valid ones"
exit 0
