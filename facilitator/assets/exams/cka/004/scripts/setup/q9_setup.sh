#!/bin/bash
set -e

# Question 9: existing user defined PriorityClasses plus a workload without one
kubectl create namespace priority --dry-run=client -o yaml | kubectl apply -f -

kubectl delete deployment edge-proxy -n priority --ignore-not-found=true
kubectl delete priorityclass edge-critical --ignore-not-found=true

# PriorityClass values are immutable, so re-seed them from scratch every time
kubectl delete priorityclass helioscale-bulk --ignore-not-found=true
kubectl delete priorityclass helioscale-standard --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: helioscale-bulk
value: 12000
globalDefault: false
description: "Batch and reporting workloads"
---
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: helioscale-standard
value: 45000
globalDefault: false
description: "Standard customer facing workloads"
EOF

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: edge-proxy
  namespace: priority
spec:
  replicas: 2
  selector:
    matchLabels:
      app: edge-proxy
  template:
    metadata:
      labels:
        app: edge-proxy
    spec:
      containers:
      - name: proxy
        image: nginx:1.27.4
        ports:
        - containerPort: 80
EOF

kubectl rollout status deployment/edge-proxy -n priority --timeout=180s || true

echo "Setup completed for Question 9"
