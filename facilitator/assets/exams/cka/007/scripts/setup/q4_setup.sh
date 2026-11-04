#!/bin/bash
set -e

# Question 4: a Deployment for the scale subresource to act on.
kubectl create namespace rbac-deploy --dry-run=client -o yaml | kubectl apply -f -

kubectl delete rolebinding release-bot-scaler -n rbac-deploy --ignore-not-found=true
kubectl delete role scaler -n rbac-deploy --ignore-not-found=true
kubectl delete serviceaccount release-bot -n rbac-deploy --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: storefront
  namespace: rbac-deploy
spec:
  replicas: 1
  selector:
    matchLabels:
      app: storefront
  template:
    metadata:
      labels:
        app: storefront
    spec:
      containers:
      - name: web
        image: nginx:1.27-alpine
        ports:
        - containerPort: 80
YAML

echo "Setup completed for Question 4"
