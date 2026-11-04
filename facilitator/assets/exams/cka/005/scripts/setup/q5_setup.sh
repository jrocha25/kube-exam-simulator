#!/bin/bash
set -e

# Question 5: a Deployment that already declares CPU and memory requests, so the
# candidate only has to build the autoscaler.
kubectl create namespace scale-web --dry-run=client -o yaml | kubectl apply -f -

kubectl delete horizontalpodautoscaler storefront-hpa -n scale-web --ignore-not-found=true
kubectl delete deployment storefront -n scale-web --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: storefront
  namespace: scale-web
spec:
  replicas: 2
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
        image: nginx:1.27.4
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 500m
            memory: 256Mi
YAML

kubectl rollout status deployment/storefront -n scale-web --timeout=180s || true

echo "Setup completed for Question 5"
