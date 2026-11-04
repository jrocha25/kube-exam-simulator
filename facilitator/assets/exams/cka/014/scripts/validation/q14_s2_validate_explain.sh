#!/bin/bash
set -e

FILE=/tmp/exam/q14/retention-doc.txt

if [[ ! -s "$FILE" ]]; then
    echo "❌ $FILE does not exist or is empty"
    exit 1
fi

# Recomputed live from the schema; explain wraps long text, so compare with all
# whitespace squeezed.
DESCRIPTION=$(kubectl get crd tideforecasts.tides.harbor.io \
    -o jsonpath='{.spec.versions[0].schema.openAPIV3Schema.properties.spec.properties.retention.description}' 2>/dev/null || true)
if [[ -z "$DESCRIPTION" ]]; then
    echo "❌ The TideForecast CRD has no retention description to compare against"
    exit 1
fi

squeeze() { tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//'; }
if ! squeeze < "$FILE" | grep -qF "$(echo "$DESCRIPTION" | squeeze)"; then
    echo "❌ $FILE does not contain the documentation of spec.retention"
    exit 1
fi

if ! grep -Eq 'FIELD:[[:space:]]+retention' "$FILE"; then
    echo "❌ $FILE is not kubectl explain output for the retention field"
    exit 1
fi

echo "✅ $FILE holds kubectl explain output for TideForecast spec.retention"
exit 0
