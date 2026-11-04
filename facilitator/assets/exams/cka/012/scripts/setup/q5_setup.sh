#!/bin/bash
set -e

# Question 5: the same nine settings, each of which belongs at one of three
# levels of a CronJob. Nothing is staged but the namespace -- the question is
# entirely about where each field goes.
#
# A CronJob the candidate created on a previous attempt would hand over the whole
# question, so it is removed on every warm-up.

NAMESPACE="wl-digest"
CRONJOB="trace-compactor"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete cronjob "$CRONJOB" -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true

echo "Setup completed for Question 5"
