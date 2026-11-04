#!/bin/bash
set -e

# Question 9: two namespaces, so the grant can be proven to stop at the boundary.
for ns in rbac-app rbac-app-staging; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl delete rolebinding report-runner-read -n rbac-app --ignore-not-found=true
kubectl delete role report-reader -n rbac-app --ignore-not-found=true
kubectl delete serviceaccount report-runner -n rbac-app --ignore-not-found=true

echo "Setup completed for Question 9"
