#!/bin/bash
set -e

REPO_NAME="podinfo"
REPO_URL="https://stefanprodan.github.io/podinfo"

URL=$(helm repo list -o json 2>/dev/null | jq -r --arg n "$REPO_NAME" '[.[] | select(.name==$n) | .url][0] // empty')
if [[ -z "$URL" ]]; then
    echo "❌ Helm repository '$REPO_NAME' has not been added"
    exit 1
fi

if [[ "${URL%/}" != "$REPO_URL" ]]; then
    echo "❌ Repository '$REPO_NAME' points at '$URL', expected '$REPO_URL'"
    exit 1
fi

echo "✅ Helm repository '$REPO_NAME' is configured with the correct URL"
exit 0
