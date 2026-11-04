#!/bin/bash

set -e

# Question 1: the simplest possible starting point -- one server, one client and
# no policy at all, so the candidate's default-deny is the only thing standing
# between them. Bare Pods rather than Deployments so validation can exec into
# them by name and read .status.podIP.

NAMESPACE="np-baseline"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete pod web client -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: ${NAMESPACE}
  labels:
    app: web
spec:
  containers:
  - name: web
    image: nginx:1.27.4
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: ${NAMESPACE}
  labels:
    app: client
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
YAML

kubectl wait --for=condition=Ready pod/web pod/client -n "$NAMESPACE" --timeout=120s || true

echo "Setup completed for Question 1"
