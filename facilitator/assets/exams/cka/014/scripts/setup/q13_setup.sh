#!/bin/bash
set -e

# Question 13: divide node02's allocatable resources between the three Pods of a
# Deployment pinned there. node02 has been cordoned since q0 so that no other
# fixture took a share of it; release it now. Fixtures created after this
# script may still land there, which is why the question asks for headroom.

NAMESPACE="crane-sim"
DEPLOYMENT="crane-sim"

NODE02=$(grep '^node02=' /tmp/exam/nodes.env | cut -d= -f2)
[ -n "$NODE02" ] && kubectl uncordon "$NODE02" >/dev/null 2>&1 || true

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT
  namespace: $NAMESPACE
spec:
  replicas: 0
  selector:
    matchLabels:
      app: $DEPLOYMENT
  template:
    metadata:
      labels:
        app: $DEPLOYMENT
    spec:
      nodeSelector:
        ck-x.io/alias: node02
      initContainers:
      - name: load-terrain
        image: busybox:1.36
        command: ["sh", "-c", "echo loading quay terrain; sleep 2"]
      containers:
      - name: simulator
        image: nginx:1.27.4
YAML

echo "Setup for question 13 completed"
