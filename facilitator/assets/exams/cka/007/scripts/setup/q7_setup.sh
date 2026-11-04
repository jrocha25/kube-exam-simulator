#!/bin/bash
set -e

# Question 7: non-resource URLs. Only the ServiceAccount's namespace is seeded.
kubectl create namespace rbac-probe --dry-run=client -o yaml | kubectl apply -f -

kubectl delete clusterrolebinding probe-agent-endpoints --ignore-not-found=true
kubectl delete clusterrole endpoint-prober --ignore-not-found=true
kubectl delete serviceaccount probe-agent -n rbac-probe --ignore-not-found=true

echo "Setup completed for Question 7"
