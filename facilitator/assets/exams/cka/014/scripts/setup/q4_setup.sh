#!/bin/bash
set -e

# Question 4: a HorizontalPodAutoscaler with scale-down behaviour. Grading reads
# the HPA's spec only, but the exam environment always has a Metrics API, so
# install metrics-server for realism -- without waiting for it.

NAMESPACE="hpa-crane"
DEPLOYMENT="crane-telemetry"
METRICS=/tmp/exam-assets/scripts/setup/files/metrics-server-v0.8.0.yaml

kubectl apply -f "$METRICS" >/dev/null || echo "WARNING: could not install metrics-server"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete hpa --all -n "$NAMESPACE" --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT
  namespace: $NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $DEPLOYMENT
  template:
    metadata:
      labels:
        app: $DEPLOYMENT
    spec:
      containers:
      - name: telemetry
        image: nginx:1.27.4
        resources:
          requests:
            cpu: 100m
            memory: 64Mi
YAML

echo "Setup for question 4 completed"
