#!/bin/bash
set -e

# Question 12: a DaemonSet that has to tolerate the control plane taint.
# Only the namespace is staged; a previous attempt's DaemonSet is removed.

NAMESPACE="ds-deice"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete daemonset deice -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true

echo "Setup completed for Question 12"
