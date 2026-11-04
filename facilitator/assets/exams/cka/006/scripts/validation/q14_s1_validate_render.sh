#!/bin/bash
set -e

OVERLAY="/tmp/exam/q14/overlays/staging"

if ! OUT=$(kubectl kustomize "$OVERLAY" 2>&1); then
    echo "❌ '$OVERLAY' still fails to render:"
    echo "$OUT" | head -3
    exit 1
fi

if [[ -z "$OUT" ]]; then
    echo "❌ '$OVERLAY' renders successfully but produces no output"
    exit 1
fi

RENDERED="/tmp/exam/q14/rendered.yaml"
if [[ ! -s "$RENDERED" ]]; then
    echo "❌ '$RENDERED' is missing or empty"
    exit 1
fi

echo "✅ '$OVERLAY' renders, and its output was written to '$RENDERED'"
exit 0
