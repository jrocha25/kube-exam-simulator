#!/bin/bash
set -e

# Question 9: one init container that must finish, and two regular containers.
# Nothing is staged but the namespace -- the question is the Pod's shape, and the
# checks count containers, so a Pod left behind by a previous attempt would hand
# the whole thing over.

NAMESPACE="wl-waveform"
POD="waveform-writer"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found=true --timeout=60s >/dev/null 2>&1 || true

echo "Setup completed for Question 9"
