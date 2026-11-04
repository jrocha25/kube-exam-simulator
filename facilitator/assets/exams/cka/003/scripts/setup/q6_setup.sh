#!/bin/bash
set -e

# Question 6: Deployment, Service and Ingress
kubectl create namespace web-shop --dry-run=client -o yaml | kubectl apply -f -

kubectl delete ingress shop-web-ing -n web-shop --ignore-not-found=true
kubectl delete service shop-web-svc -n web-shop --ignore-not-found=true
kubectl delete deployment shop-web -n web-shop --ignore-not-found=true

echo "Setup completed for Question 6"
