#!/bin/bash
set -e

RENDERED="/tmp/exam/q12/rendered.yaml"

if [[ ! -s "$RENDERED" ]]; then
    echo "❌ '$RENDERED' is missing or empty"
    exit 1
fi

# The rendered file must be the overlay's output, not the base's: it has to carry
# the transformations rather than merely be valid YAML.
if ! grep -q "name: prod-trade-app" "$RENDERED"; then
    echo "❌ '$RENDERED' does not contain the prefixed name 'prod-trade-app'"
    exit 1
fi
if ! grep -q "namespace: kustom-prod" "$RENDERED"; then
    echo "❌ '$RENDERED' does not place the resource in the 'kustom-prod' namespace"
    exit 1
fi
if ! grep -q "nginx:1.27.4" "$RENDERED"; then
    echo "❌ '$RENDERED' does not use the image 'nginx:1.27.4'"
    exit 1
fi

echo "✅ '$RENDERED' holds the rendered production overlay"
exit 0
