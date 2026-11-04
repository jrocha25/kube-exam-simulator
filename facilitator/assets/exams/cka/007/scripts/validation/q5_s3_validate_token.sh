#!/bin/bash
set -e

TOKEN_FILE="/tmp/exam/q5/token.jwt"
EXPECTED="system:serviceaccount:rbac-token:job-runner"

if [[ ! -s "$TOKEN_FILE" ]]; then
    echo "❌ '$TOKEN_FILE' is missing or empty"
    exit 1
fi

TOKEN=$(tr -d '[:space:]' < "$TOKEN_FILE")
if [[ "$(grep -o '\.' <<< "$TOKEN" | wc -l)" != "2" ]]; then
    echo "❌ '$TOKEN_FILE' does not contain a JWT (expected three dot separated segments)"
    exit 1
fi

# A TokenReview proves the token really authenticates, not merely that it parses.
REVIEW=$(mktemp)
trap 'rm -f "$REVIEW"' EXIT
cat > "$REVIEW" <<YAML
apiVersion: authentication.k8s.io/v1
kind: TokenReview
spec:
  token: "$TOKEN"
YAML

RESULT=$(kubectl create -f "$REVIEW" -o json 2>/dev/null || true)
if [[ -z "$RESULT" ]]; then
    echo "❌ The API server could not review the token in '$TOKEN_FILE'"
    exit 1
fi

AUTHENTICATED=$(echo "$RESULT" | jq -r '.status.authenticated // false')
USERNAME=$(echo "$RESULT" | jq -r '.status.user.username // ""')

if [[ "$AUTHENTICATED" != "true" ]]; then
    echo "❌ The token in '$TOKEN_FILE' is not accepted by the API server"
    exit 1
fi
if [[ "$USERNAME" != "$EXPECTED" ]]; then
    echo "❌ The token authenticates as '${USERNAME:-<none>}', expected '$EXPECTED'"
    exit 1
fi

echo "✅ '$TOKEN_FILE' holds a valid token that authenticates as '$EXPECTED'"
exit 0
