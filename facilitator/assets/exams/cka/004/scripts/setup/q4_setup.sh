#!/bin/bash
set -e

# Question 4: deployment with CPU requests, ready for a HorizontalPodAutoscaler
kubectl create namespace checkout --dry-run=client -o yaml | kubectl apply -f -

kubectl delete horizontalpodautoscaler checkout-hpa -n checkout --ignore-not-found=true
kubectl delete deployment checkout-api -n checkout --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-api
  namespace: checkout
spec:
  replicas: 2
  selector:
    matchLabels:
      app: checkout-api
  template:
    metadata:
      labels:
        app: checkout-api
    spec:
      containers:
      - name: api
        image: nginx:1.27.4
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
          limits:
            cpu: 300m
            memory: 128Mi
EOF

kubectl rollout status deployment/checkout-api -n checkout --timeout=180s || true

echo "Setup completed for Question 4"
