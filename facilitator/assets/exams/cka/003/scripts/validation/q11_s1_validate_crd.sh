#!/bin/bash
set -e

CRD_NAME="backupjobs.ops.example.com"

if ! kubectl get crd "$CRD_NAME" &> /dev/null; then
    echo "❌ CustomResourceDefinition '$CRD_NAME' not found"
    exit 1
fi

GROUP=$(kubectl get crd "$CRD_NAME" -o jsonpath='{.spec.group}')
if [[ "$GROUP" != "ops.example.com" ]]; then
    echo "❌ Incorrect group. Expected 'ops.example.com', got '$GROUP'"
    exit 1
fi

KIND=$(kubectl get crd "$CRD_NAME" -o jsonpath='{.spec.names.kind}')
if [[ "$KIND" != "BackupJob" ]]; then
    echo "❌ Incorrect kind. Expected 'BackupJob', got '$KIND'"
    exit 1
fi

SCOPE=$(kubectl get crd "$CRD_NAME" -o jsonpath='{.spec.scope}')
if [[ "$SCOPE" != "Namespaced" ]]; then
    echo "❌ Incorrect scope. Expected 'Namespaced', got '$SCOPE'"
    exit 1
fi

VERSION=$(kubectl get crd "$CRD_NAME" -o json | jq -r '[.spec.versions[] | select(.name == "v1" and .served == true and .storage == true)] | length')
if [[ "$VERSION" == "0" ]]; then
    echo "❌ CRD '$CRD_NAME' does not serve and store version 'v1'"
    exit 1
fi

ESTABLISHED=$(kubectl get crd "$CRD_NAME" -o jsonpath='{.status.conditions[?(@.type=="Established")].status}')
if [[ "$ESTABLISHED" != "True" ]]; then
    echo "❌ CRD '$CRD_NAME' is not Established (got: '$ESTABLISHED')"
    exit 1
fi

echo "✅ CustomResourceDefinition '$CRD_NAME' is applied and Established"
exit 0
