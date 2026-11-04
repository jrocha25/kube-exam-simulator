#!/bin/bash
set -e

# Question 15: immutable ConfigMap and Secret. Nothing seeded beyond the
# namespace -- the candidate creates both objects, and the marks are for getting
# "immutable: true" onto them, which kubectl has no flag for.

NAMESPACE="compliance"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete configmap audit-config -n "$NAMESPACE" --ignore-not-found=true
kubectl delete secret audit-keys -n "$NAMESPACE" --ignore-not-found=true

echo "Setup completed for Question 15"
