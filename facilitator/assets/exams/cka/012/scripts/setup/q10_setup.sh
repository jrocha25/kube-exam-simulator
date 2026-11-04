#!/bin/bash
set -e

# Question 10: the same primitives as question 9, arranged the other way round --
# one regular container and two init containers, the second of which is a native
# sidecar (restartPolicy: Always) and stays up.
#
# Paired with question 9 on purpose: between them they are the distinction a mock
# exam marked wrong, where a native sidecar was counted as a regular container.

NAMESPACE="wl-shipper"
POD="trace-shipper"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found=true --timeout=60s >/dev/null 2>&1 || true

echo "Setup completed for Question 10"
