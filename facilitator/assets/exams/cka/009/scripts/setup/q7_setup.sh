#!/bin/bash

set -e

# Question 7: preferred node affinity, two competing weights, no required block.
#
# Graded on the spec and on every replica being ready -- never on placement. A
# preference is a scoring hint, so asserting where the pods landed would be
# grading the scheduler's mood rather than the candidate's answer.

NAMESPACE="sched-prefer"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment --all -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true

echo "Setup completed for Question 7"
