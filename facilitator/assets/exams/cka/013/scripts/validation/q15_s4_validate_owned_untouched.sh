#!/bin/bash
set -e

NAMESPACE="ts-cargo"
STATE_DIR=/tmp/exam/q15

# A constraint: true of an untouched namespace, so it only counts once the
# rollout the question asks for has completed.
STATUS=$(kubectl get deployment cargo-api -n "$NAMESPACE" -o jsonpath='{.status.updatedReplicas}/{.status.readyReplicas}' 2>/dev/null || true)
if [[ "$STATUS" != "2/2" ]]; then
    echo "❌ cargo-api has not finished rolling out"
    exit 1
fi

SECRET=$(kubectl get secret relay-secrets -n "$NAMESPACE" -o json 2>/dev/null | jq -c '{uid: .metadata.uid, data: .data}' | sha256sum)
if [[ "$SECRET" != "$(cat "$STATE_DIR/secret.sha256" 2>/dev/null)" ]]; then
    echo "❌ The Secret relay-secrets was modified, replaced or deleted"
    exit 1
fi

QUOTA=$(kubectl get resourcequota cargo-quota -n "$NAMESPACE" -o json 2>/dev/null | jq -c '{uid: .metadata.uid, hard: .spec.hard, scopes: .spec.scopes, scopeSelector: .spec.scopeSelector}' | sha256sum)
if [[ "$QUOTA" != "$(cat "$STATE_DIR/quota.sha256" 2>/dev/null)" ]]; then
    echo "❌ The ResourceQuota cargo-quota was modified, replaced or deleted"
    exit 1
fi

echo "✅ relay-secrets and cargo-quota are untouched"
exit 0
