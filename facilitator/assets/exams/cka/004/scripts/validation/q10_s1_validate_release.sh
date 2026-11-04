#!/bin/bash
set -e

NAMESPACE="edge-helm"
RELEASE="web-edge"

RELEASES=$(helm list -n "$NAMESPACE" -o json 2>/dev/null || echo '[]')

FOUND=$(echo "$RELEASES" | jq --arg r "$RELEASE" '[.[] | select(.name == $r)] | length')
if [[ "$FOUND" == "0" ]]; then
    echo "❌ Helm release '$RELEASE' not found in namespace '$NAMESPACE'"
    exit 1
fi

CHART=$(echo "$RELEASES" | jq -r --arg r "$RELEASE" '.[] | select(.name == $r) | .chart')
if [[ "$CHART" != "helioscale-web-1.0.0" ]]; then
    echo "❌ Release '$RELEASE' was installed from '$CHART' instead of the local chart 'helioscale-web-1.0.0'"
    exit 1
fi

STATUS=$(echo "$RELEASES" | jq -r --arg r "$RELEASE" '.[] | select(.name == $r) | .status')
if [[ "$STATUS" != "deployed" ]]; then
    echo "❌ Release '$RELEASE' is in status '$STATUS' instead of 'deployed'"
    exit 1
fi

REVISION=$(echo "$RELEASES" | jq -r --arg r "$RELEASE" '.[] | select(.name == $r) | .revision')
if [[ "$REVISION" != "3" ]]; then
    echo "❌ Release '$RELEASE' is at revision '$REVISION'. Expected revision 3 after an install, an upgrade and a rollback"
    exit 1
fi

echo "✅ Helm release '$RELEASE' is deployed at revision 3"
exit 0
