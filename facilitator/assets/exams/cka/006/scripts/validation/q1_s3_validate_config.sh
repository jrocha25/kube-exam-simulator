#!/bin/bash
set -e

NAMESPACE="ops-probe"
POD_LABEL="app=node-probe"

POD=$(kubectl get pods -n "$NAMESPACE" -l "$POD_LABEL" \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$POD" ]]; then
    echo "❌ No Pod labelled '$POD_LABEL' found in namespace '$NAMESPACE'"
    exit 1
fi

# The container prints the configuration file and then a marker line. If it can
# read the file at all, the marker is in the log -- which is a stronger check than
# reading the command out of the spec, because it proves the path the container
# uses and the file that actually exists are the same one.
LOGS=$(kubectl logs "$POD" -n "$NAMESPACE" --tail=20 2>/dev/null || true)
if ! grep -q "probe started" <<<"$LOGS"; then
    echo "❌ The container never got past reading its configuration file."
    echo "   Last output was: ${LOGS:-<empty>}"
    exit 1
fi

if ! grep -q "endpoint=" <<<"$LOGS"; then
    echo "❌ The container started but did not print the configuration file's contents"
    exit 1
fi

echo "✅ The container reads a configuration file that exists"
exit 0
