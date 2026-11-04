#!/bin/bash
set -e

# Question 2: nothing to seed but the namespace the SA-free question is filed
# under; the grant itself is cluster scoped and goes to a Group and a User.
kubectl create namespace rbac-audit --dry-run=client -o yaml | kubectl apply -f -

kubectl delete clusterrolebinding infra-auditors --ignore-not-found=true
kubectl delete clusterrole infra-auditor --ignore-not-found=true

echo "Setup completed for Question 2"
