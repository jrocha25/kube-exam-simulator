#!/bin/bash
set -e

FILE="/tmp/exam/q15/rendered.yaml"

if [[ ! -s "$FILE" ]]; then
    echo "❌ '$FILE' does not exist or is empty"
    exit 1
fi

# --dry-run=client only parses and validates locally; nothing is sent to the
# cluster, which matters because this question forbids applying the overlay.
DEPLOY=$(kubectl apply -f "$FILE" --dry-run=client -o json 2>/dev/null \
    | jq -s '[.[] | if .kind == "List" then .items[] else . end | select(.kind=="Deployment")][0] // empty')
if [[ -z "$DEPLOY" ]]; then
    echo "❌ '$FILE' contains no Deployment"
    exit 1
fi

NS=$(echo "$DEPLOY" | jq -r '.metadata.namespace // empty')
if [[ "$NS" != "kustom-fix" ]]; then
    echo "❌ The rendered Deployment is in namespace '${NS:-<none>}', expected 'kustom-fix'"
    exit 1
fi

REPLICAS=$(echo "$DEPLOY" | jq -r '.spec.replicas')
if [[ "$REPLICAS" != "5" ]]; then
    echo "❌ The rendered Deployment declares '$REPLICAS' replicas, expected '5'"
    exit 1
fi

IMAGE=$(echo "$DEPLOY" | jq -r '.spec.template.spec.containers[0].image')
if [[ "$IMAGE" != "nginx:1.27.4" ]]; then
    echo "❌ The rendered Deployment runs '$IMAGE', expected 'nginx:1.27.4'"
    exit 1
fi

echo "✅ The rendered Deployment is in 'kustom-fix' with 5 replicas of nginx:1.27.4"
exit 0
