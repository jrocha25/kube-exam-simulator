#!/bin/bash
set -e

# Question 11: Service plumbing. A Deployment whose container port is named, so
# the Service has to target the name rather than the number, plus a NodePort and
# an ExternalName alias. Nothing is broken.

NAMESPACE="svc-edge"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment,service --all -n "$NAMESPACE" --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: edge-web
  namespace: $NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: edge-web
  template:
    metadata:
      labels:
        app: edge-web
    spec:
      containers:
      - name: web
        image: nginx:1.27.4
        ports:
        - name: http-web
          containerPort: 80
YAML

kubectl rollout status deployment/edge-web -n "$NAMESPACE" --timeout=180s \
    || echo "WARNING: edge-web did not become ready in time"

echo "Setup completed for Question 11"
