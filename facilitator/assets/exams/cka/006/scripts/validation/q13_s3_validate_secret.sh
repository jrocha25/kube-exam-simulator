#!/bin/bash
set -e

NAMESPACE="kustom-stage"
EXPECTED_VALUE="stage-7f3c"

# secretGenerator appends a content hash to the name, so match on the prefix.
NAME=$(kubectl get secrets -n "$NAMESPACE" -o json 2>/dev/null \
    | jq -r '[.items[] | select(.metadata.name | startswith("api-credentials")) | .metadata.name] | first // empty')
if [[ -z "$NAME" ]]; then
    echo "❌ No Secret whose name begins with 'api-credentials' exists in '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get secret "$NAME" -n "$NAMESPACE" -o json)

TYPE=$(echo "$JSON" | jq -r '.type')
if [[ "$TYPE" != "Opaque" ]]; then
    echo "❌ Secret '$NAME' is of type '$TYPE', expected 'Opaque'"
    exit 1
fi

VALUE=$(echo "$JSON" | jq -r '.data.API_TOKEN // empty' | base64 -d 2>/dev/null || true)
if [[ "$VALUE" != "$EXPECTED_VALUE" ]]; then
    echo "❌ Secret '$NAME' holds API_TOKEN='${VALUE:-<missing>}', expected '$EXPECTED_VALUE'"
    exit 1
fi

echo "✅ The generated Secret '$NAME' holds API_TOKEN=$EXPECTED_VALUE"
exit 0
