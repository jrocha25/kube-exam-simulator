#!/bin/bash
set -e

# Question 5: the candidate writes a token to /tmp/exam/q5, so the directory has
# to exist before the exam starts.
kubectl create namespace rbac-token --dry-run=client -o yaml | kubectl apply -f -

mkdir -p /tmp/exam/q5
rm -f /tmp/exam/q5/token.jwt

kubectl delete pod probe -n rbac-token --ignore-not-found=true
kubectl delete serviceaccount job-runner -n rbac-token --ignore-not-found=true

echo "Setup completed for Question 5"
