#!/bin/bash
set -e

# Question 9: RBAC for an automation service account
kubectl create namespace ops-rbac --dry-run=client -o yaml | kubectl apply -f -

kubectl delete rolebinding deploy-bot-reader -n ops-rbac --ignore-not-found=true
kubectl delete clusterrole deployment-reader --ignore-not-found=true
kubectl delete serviceaccount deploy-bot -n ops-rbac --ignore-not-found=true

echo "Setup completed for Question 9"
