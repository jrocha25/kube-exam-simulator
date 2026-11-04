#!/bin/bash
set -e

# Question 15: Service with a wrong selector and a wrong target port
kubectl create namespace ts-service --dry-run=client -o yaml | kubectl apply -f -

kubectl delete service catalog-svc -n ts-service --ignore-not-found=true
kubectl delete deployment catalog -n ts-service --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
  namespace: ts-service
spec:
  replicas: 3
  selector:
    matchLabels:
      app: catalog
  template:
    metadata:
      labels:
        app: catalog
    spec:
      containers:
      - name: web
        image: nginx:1.27.4
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: catalog-svc
  namespace: ts-service
spec:
  type: ClusterIP
  selector:
    app: catalog-api
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8080
EOF

kubectl rollout status deployment/catalog -n ts-service --timeout=180s || true

echo "Setup completed for Question 15"
