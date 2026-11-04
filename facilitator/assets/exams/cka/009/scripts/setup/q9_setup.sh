#!/bin/bash

set -e

# Question 9: podAffinity across namespaces -- the first positive podAffinity in
# the repo.
#
# The lesson is the default: podAffinity matches only within the pod's OWN
# namespace, so a rule that names the collector's labels but not its namespace
# matches nothing and leaves every replica Pending. That failure is the whole
# point, so the collector is deliberately somewhere else.
#
# It is pinned to node01 so "same node as the collector" is a single, checkable
# answer rather than whichever node the scheduler happened to pick.

NAMESPACE="sched-podaff"
INFRA_NS="sched-podaff-infra"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$INFRA_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment --all -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true
kubectl delete deployment --all -n "$INFRA_NS" --ignore-not-found=true --timeout=60s || true

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: depot-telemetry
  namespace: ${INFRA_NS}
  labels:
    app: depot-telemetry
spec:
  replicas: 1
  selector:
    matchLabels:
      app: depot-telemetry
  template:
    metadata:
      labels:
        app: depot-telemetry
    spec:
      nodeSelector:
        ck-x.io/alias: node01
      containers:
      - name: collector
        image: nginx:1.27.4
        ports:
        - containerPort: 80
YAML

kubectl wait --for=condition=Available deployment/depot-telemetry -n "$INFRA_NS" --timeout=120s || true

echo "Setup completed for Question 9"
