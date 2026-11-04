#!/bin/bash
set -e

# Question 5: Deployment with a topology spread constraint
kubectl create namespace spread-lab --dry-run=client -o yaml | kubectl apply -f -

kubectl delete deployment spread-web -n spread-lab --ignore-not-found=true

echo "Setup completed for Question 5"
