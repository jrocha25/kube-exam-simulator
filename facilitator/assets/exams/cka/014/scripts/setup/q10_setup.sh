#!/bin/bash
set -e

# Question 10: a PriorityClass whose value is derived from the existing ones.
# The highest user-defined class is deliberately not the one called "critical".

NAMESPACE="pilot-ops"
DEPLOYMENT="pilot-dispatch"

kubectl delete priorityclass berth-urgent --ignore-not-found=true

for pc in harbor-batch:1500 harbor-critical:600000 harbor-ops:750000; do
    kubectl apply -f - <<YAML
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: ${pc%%:*}
value: ${pc##*:}
globalDefault: false
preemptionPolicy: PreemptLowerPriority
description: Harbor workload tier ${pc%%:*}
YAML
done

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
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
      priorityClassName: harbor-batch
      containers:
      - name: dispatch
        image: nginx:1.27.4
YAML

echo "Setup for question 10 completed"
