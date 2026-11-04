#!/bin/bash
set -e

# Question 12: build a base and an overlay from nothing. This is the direct
# remediation for the Kustomize question in the mock exam, so the candidate
# writes every file: nothing is pre-created except the empty directories and the
# target namespace.

NAMESPACE="kustom-prod"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment,service,configmap --all -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true

rm -rf /tmp/exam/q12
mkdir -p /tmp/exam/q12/base /tmp/exam/q12/overlays/production

echo "Setup completed for Question 12"
