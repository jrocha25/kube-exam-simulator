#!/bin/bash
set -e

# Question 12: a Deployment that declares no container ports, to be exposed on a
# fixed NodePort through a named port.

NAMESPACE="tally"
DEPLOYMENT="tally-board"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete service tally-board-np -n "$NAMESPACE" --ignore-not-found=true

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
      - name: board
        image: nginx:1.27.4
YAML

echo "Setup for question 12 completed"
