#!/bin/bash
set -e

NAMESPACE="registry-audit"
LIMITRANGE="audit-defaults"
EXPECTED_DEFAULT="256Mi"
EXPECTED_REQUEST="128Mi"
EXPECTED_MAX="512Mi"

if ! kubectl get limitrange "$LIMITRANGE" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ LimitRange '$LIMITRANGE' not found in namespace '$NAMESPACE'"
    exit 1
fi

LIMIT_JSON=$(kubectl get limitrange "$LIMITRANGE" -n "$NAMESPACE" -o json)

# The Container limit type is the only one that defaults an individual container.
CONTAINER_ENTRIES=$(echo "$LIMIT_JSON" | jq '[.spec.limits[]? | select(.type == "Container")] | length')
if [[ "$CONTAINER_ENTRIES" == "0" ]]; then
    echo "❌ LimitRange '$LIMITRANGE' has no limit entry of type 'Container'"
    exit 1
fi

DEFAULT_MEM=$(echo "$LIMIT_JSON" | jq -r '[.spec.limits[]? | select(.type == "Container") | .default.memory // empty][0] // ""')
REQUEST_MEM=$(echo "$LIMIT_JSON" | jq -r '[.spec.limits[]? | select(.type == "Container") | .defaultRequest.memory // empty][0] // ""')
MAX_MEM=$(echo "$LIMIT_JSON" | jq -r '[.spec.limits[]? | select(.type == "Container") | .max.memory // empty][0] // ""')

if [[ "$DEFAULT_MEM" != "$EXPECTED_DEFAULT" ]]; then
    echo "❌ Default memory limit is '${DEFAULT_MEM:-<unset>}', expected '$EXPECTED_DEFAULT'"
    exit 1
fi

if [[ "$REQUEST_MEM" != "$EXPECTED_REQUEST" ]]; then
    echo "❌ Default memory request is '${REQUEST_MEM:-<unset>}', expected '$EXPECTED_REQUEST'"
    exit 1
fi

if [[ "$MAX_MEM" != "$EXPECTED_MAX" ]]; then
    echo "❌ Maximum memory limit is '${MAX_MEM:-<unset>}', expected '$EXPECTED_MAX'"
    exit 1
fi

echo "✅ LimitRange '$LIMITRANGE' defaults memory to $EXPECTED_DEFAULT/$EXPECTED_REQUEST and caps it at $EXPECTED_MAX"
exit 0
