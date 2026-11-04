#!/bin/bash
set -e

# Question 7: RBAC for an automation account, scoped to a single namespace
kubectl create namespace delivery --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace delivery-staging --dry-run=client -o yaml | kubectl apply -f -

kubectl delete rolebinding pipeline-binding -n delivery --ignore-not-found=true
kubectl delete clusterrolebinding pipeline-binding --ignore-not-found=true
kubectl delete clusterrole deploy-manager --ignore-not-found=true
kubectl delete serviceaccount pipeline-bot -n delivery --ignore-not-found=true

echo "Setup completed for Question 7"
