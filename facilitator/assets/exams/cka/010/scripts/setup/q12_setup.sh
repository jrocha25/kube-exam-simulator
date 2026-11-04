#!/bin/bash
set -e

# Question 12: a multi-port Service that has to reach container ports by name.
# The Deployment is staged with two containers, each publishing a *named* port
# -- nginx on "http" and a busybox httpd on "metrics" -- so that a Service
# written with numeric targetPorts works too and the "by name" requirement has
# to be graded on the spec, while reachability is graded live from the exporter
# container, whose busybox has wget.

NAMESPACE="svc-telemetry"
DEPLOYMENT="telemetry"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete service "$DEPLOYMENT" -n "$NAMESPACE" --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT
  namespace: $NAMESPACE
  labels:
    app: $DEPLOYMENT
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $DEPLOYMENT
  template:
    metadata:
      labels:
        app: $DEPLOYMENT
        tier: edge
    spec:
      containers:
      - name: web
        image: nginx:1.27.4
        ports:
        - name: http
          containerPort: 80
      - name: exporter
        image: busybox:1.36
        command: ["sh", "-c", "mkdir -p /www && echo 'telemetry_up 1' > /www/metrics && exec httpd -f -p 9100 -h /www"]
        ports:
        - name: metrics
          containerPort: 9100
YAML

kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=120s \
    || echo "WARNING: $DEPLOYMENT did not become ready"

echo "Setup completed for Question 12"
