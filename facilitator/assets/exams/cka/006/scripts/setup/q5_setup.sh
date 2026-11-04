#!/bin/bash
set -e

# Question 5: node maintenance. A Deployment spread across both workers plus a
# DaemonSet, so draining has something to evict and something it must be told to
# ignore. Nothing is broken; the marks are for doing the drain correctly and
# putting the node back into service afterwards.

NAMESPACE="node-maint"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment,daemonset --all -n "$NAMESPACE" --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-web
  namespace: $NAMESPACE
spec:
  replicas: 4
  selector:
    matchLabels:
      app: shop-web
  template:
    metadata:
      labels:
        app: shop-web
    spec:
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: ScheduleAnyway
        labelSelector:
          matchLabels:
            app: shop-web
      containers:
      - name: web
        image: nginx:1.27.4
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: log-shipper
  namespace: $NAMESPACE
spec:
  selector:
    matchLabels:
      app: log-shipper
  template:
    metadata:
      labels:
        app: log-shipper
    spec:
      tolerations:
      - operator: Exists
      containers:
      - name: shipper
        image: busybox:1.36
        command: ["sh", "-c", "sleep 86400"]
YAML

# Make sure the node is schedulable before the exam starts, in case a previous
# attempt left it cordoned.
NODE02=$(kubectl get nodes -l ck-x.io/alias=node02 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
[ -n "$NODE02" ] && kubectl uncordon "$NODE02" >/dev/null 2>&1 || true

kubectl rollout status deployment/shop-web -n "$NAMESPACE" --timeout=180s \
    || echo "WARNING: shop-web did not become ready in time"

rm -rf /tmp/exam/q5
mkdir -p /tmp/exam/q5

echo "Setup completed for Question 5"
