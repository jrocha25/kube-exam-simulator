#!/bin/bash
set -e

# Question 8: add a native sidecar that has to be running before an existing
# plain init container starts. The kubernetes.io sidecar example appends its
# sidecar to initContainers; here that order loses the init container's output.

NAMESPACE="manifest-ops"
DEPLOYMENT="manifest-api"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: manifest-api
  namespace: manifest-ops
spec:
  replicas: 2
  selector:
    matchLabels:
      app: manifest-api
  template:
    metadata:
      labels:
        app: manifest-api
    spec:
      initContainers:
      - name: schema-migrate
        image: busybox:1.36
        command:
        - sh
        - -c
        - mkdir -p /var/log/manifest; sleep 3; for i in 1 2 3; do echo "$(date -u +%T) migrate step $i" >> /var/log/manifest/migrate.log; sleep 1; done
      containers:
      - name: api
        image: busybox:1.36
        command:
        - sh
        - -c
        - mkdir -p /var/log/manifest; while true; do echo "$(date -u +%T) api heartbeat" >> /var/log/manifest/app.log; sleep 5; done
YAML

echo "Setup for question 8 completed"
