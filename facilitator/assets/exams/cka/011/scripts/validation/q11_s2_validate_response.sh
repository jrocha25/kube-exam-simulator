#!/bin/bash
set -e

# Provenance. The clearance value is generated fresh on every warm-up and read
# from the live cluster here, so a file typed out by hand or carried over from a
# previous attempt cannot contain it -- it has to have come back from the API
# server. The resourceVersion check rules out a file assembled from the
# question text.

NAMESPACE="api-beacon"
FILE="/tmp/exam/q11/configmaps.json"

if [[ ! -s "$FILE" ]]; then
    echo "❌ '$FILE' is missing or empty"
    exit 1
fi

if ! jq -e . "$FILE" >/dev/null 2>&1; then
    echo "❌ '$FILE' is not valid JSON"
    exit 1
fi

KIND=$(jq -r '.kind // ""' "$FILE")
if [[ "$KIND" != "ConfigMapList" ]]; then
    echo "❌ '$FILE' has kind '${KIND:-none}', expected 'ConfigMapList'"
    echo "   A 403 or 401 body means the Pod's ServiceAccount token was not used."
    exit 1
fi

EXPECTED=$(kubectl get configmap runway-status -n "$NAMESPACE" -o jsonpath='{.data.clearance}' 2>/dev/null || true)
if [[ -z "$EXPECTED" ]]; then
    echo "❌ The 'runway-status' ConfigMap has no clearance value; setup did not complete"
    exit 1
fi

if ! jq -e --arg v "$EXPECTED" '[.items[]?.data?.clearance // empty] | index($v)' "$FILE" >/dev/null 2>&1; then
    echo "❌ '$FILE' does not contain the live clearance value of the 'runway-status' ConfigMap"
    exit 1
fi

if ! jq -e '.metadata.resourceVersion // empty' "$FILE" >/dev/null 2>&1; then
    echo "❌ '$FILE' carries no resourceVersion, so it did not come from the API server"
    exit 1
fi

echo "✅ The captured response is a genuine ConfigMapList from the API server"
exit 0
