#!/bin/bash
set -e

# Question 13: broken image tag -> ImagePullBackOff
kubectl create namespace ts-image --dry-run=client -o yaml | kubectl apply -f -

kubectl delete deployment billing-api -n ts-image --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: billing-api
  namespace: ts-image
spec:
  replicas: 3
  selector:
    matchLabels:
      app: billing-api
  template:
    metadata:
      labels:
        app: billing-api
    spec:
      containers:
      - name: api
        image: nginx:1.99-not-real
        ports:
        - containerPort: 80
EOF

echo "Setup completed for Question 13"
