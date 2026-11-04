#!/bin/bash
set -e

# Question 10: a cluster-scoped role granted twice over, once namespaced and once
# cluster wide. rbac-ops-secure exists only so the namespaced grant can be shown
# not to leak.
for ns in rbac-ops rbac-ops-secure; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl delete clusterrolebinding oncall-node-view --ignore-not-found=true
kubectl delete clusterrole pod-debugger node-viewer --ignore-not-found=true
kubectl delete rolebinding oncall-debug -n rbac-ops --ignore-not-found=true
kubectl delete serviceaccount oncall -n rbac-ops --ignore-not-found=true

echo "Setup completed for Question 10"
