#!/bin/bash
set -e

# Question 7: a Service with no endpoints. The Deployment relabelled its pods
# during a "tidy-up" (app=checkout-api) while the Service kept selecting the old
# label (app=checkout), so the Service resolves and connects to nothing at all.
# Everything is healthy except the one field that joins them.

NAMESPACE="svc-orders"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment,service --all -n "$NAMESPACE" --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout
  namespace: $NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: checkout-api
  template:
    metadata:
      labels:
        app: checkout-api
        tier: backend
    spec:
      containers:
      - name: api
        image: nginx:1.27.4
        ports:
        - name: http
          containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: checkout
  namespace: $NAMESPACE
spec:
  type: ClusterIP
  selector:
    app: checkout
  ports:
  - name: http
    protocol: TCP
    port: 80
    targetPort: 80
YAML

kubectl rollout status deployment/checkout -n "$NAMESPACE" --timeout=180s \
    || echo "WARNING: checkout did not become ready in time"

# A client to test from, so the candidate is not forced to create one.
# Pinned to node01 for the same reason as the other bare Pods in this lab:
# question 5 drains node02, and drain refuses to evict an uncontrolled Pod.
kubectl run probe --image=busybox:1.36 -n "$NAMESPACE" --restart=Never \
    --overrides='{"spec":{"nodeSelector":{"ck-x.io/alias":"node01"}}}' \
    --command -- sleep 86400 >/dev/null 2>&1 || true

echo "Setup completed for Question 7"
