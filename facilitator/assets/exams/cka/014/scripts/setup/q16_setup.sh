#!/bin/bash
set -e

# Question 16: a namespace enforcing the restricted Pod Security Standard and a
# Deployment whose Pod template violates it. The Deployment is admitted (with a
# warning); its ReplicaSet is not allowed to create a single Pod.

NAMESPACE="customs"
DEPLOYMENT="customs-gate"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace "$NAMESPACE" --overwrite \
    pod-security.kubernetes.io/enforce=restricted \
    pod-security.kubernetes.io/enforce-version=latest

kubectl apply -f - 2>/dev/null <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: customs-gate
  namespace: customs
spec:
  replicas: 3
  selector:
    matchLabels:
      app: customs-gate
  template:
    metadata:
      labels:
        app: customs-gate
    spec:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
      containers:
      - name: gate
        image: busybox:1.36
        command:
        - sh
        - -c
        - mkdir -p /tmp/www && echo customs-gate > /tmp/www/index.html && exec httpd -f -p 8080 -h /tmp/www
        ports:
        - containerPort: 8080
        readinessProbe:
          tcpSocket:
            port: 8080
          periodSeconds: 5
YAML

echo "Setup for question 16 completed"
