#!/bin/bash
set -e

# Question 8: NodePort Service in front of an existing Deployment
kubectl create namespace cache-tier --dry-run=client -o yaml | kubectl apply -f -

kubectl delete service cache-svc -n cache-tier --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cache
  namespace: cache-tier
spec:
  replicas: 2
  selector:
    matchLabels:
      app: cache
  template:
    metadata:
      labels:
        app: cache
    spec:
      containers:
      - name: cache
        image: redis:7.2-alpine
        ports:
        - containerPort: 6379
EOF

kubectl rollout status deployment/cache -n cache-tier --timeout=180s || true

echo "Setup completed for Question 8"
