#!/bin/bash
set -e

# Question 10: a create-only Role. Nothing is pre-created beyond the namespace;
# a previous attempt's objects are removed so the candidate starts from nothing
# and the "exists" check cannot pass for free.

NAMESPACE="rbac-tower"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete serviceaccount flightplan-writer -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true
kubectl delete role flightplan-writer -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true
kubectl delete rolebinding flightplan-writer -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true

echo "Setup completed for Question 10"
