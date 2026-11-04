#!/bin/bash
set -e

NAMESPACE="helm-tide"
RELEASE="tidewatch"
BROKEN_TAG="1.27.4-ck-x-broken"

HISTORY=$(helm history "$RELEASE" -n "$NAMESPACE" -o json 2>/dev/null || true)
if [[ -z "$HISTORY" ]]; then
    echo "❌ Release '$RELEASE' not found in namespace '$NAMESPACE'"
    exit 1
fi

ROLLBACK=$(echo "$HISTORY" | jq -r '[.[] | select(.revision > 2 and .description == "Rollback to 1")] | first | .revision // empty')
LATEST=$(echo "$HISTORY" | jq -c 'max_by(.revision)')
LATEST_REV=$(echo "$LATEST" | jq -r '.revision')
LATEST_STATUS=$(echo "$LATEST" | jq -r '.status')
LATEST_DESC=$(echo "$LATEST" | jq -r '.description')

if [[ -z "$ROLLBACK" ]] || (( LATEST_REV <= ROLLBACK )); then
    echo "❌ There is no upgrade after the rollback"
    exit 1
fi
if [[ "$LATEST_STATUS" != "deployed" || "$LATEST_DESC" != "Upgrade complete" ]]; then
    echo "❌ The latest revision $LATEST_REV is '$LATEST_STATUS' ($LATEST_DESC), not a deployed upgrade"
    exit 1
fi

VALUES=$(helm get values "$RELEASE" -n "$NAMESPACE" -o json 2>/dev/null)
check() {
    local key="$1" want="$2" got
    got=$(echo "$VALUES" | jq -r "$key // empty")
    if [[ "$got" != "$want" ]]; then
        echo "❌ User-supplied value $key is '${got:-unset}', expected '$want'"
        exit 1
    fi
}
check '.replicaCount' 2
check '.berth' north
check '.season' winter
check '.tier' priority

TAG=$(echo "$VALUES" | jq -r '.image.tag // empty')
if [[ "$TAG" == "$BROKEN_TAG" ]]; then
    echo "❌ The deployed revision still carries the broken image tag"
    exit 1
fi

echo "✅ Revision $LATEST_REV is an upgrade carrying replicaCount, berth, season and tier"
exit 0
