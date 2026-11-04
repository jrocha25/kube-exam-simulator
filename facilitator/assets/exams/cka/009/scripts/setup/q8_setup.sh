#!/bin/bash

set -e

# Question 8: anti-affinity against ANOTHER workload's label, not the pod's own.
#
# The documentation's inter-pod example is a workload spreading itself. Here a
# latency-sensitive service owned by another team is pinned to one node, and the
# candidate's batch workload has to stay off whichever node that is. A
# self-selecting answer spreads the batch pods across nodes and is perfectly free
# to put one of them on the protected node, so the placement check tells the two
# answers apart without any inspection of intent.
#
# scan-gateway lives in the SAME namespace as the candidate's workload:
# podAntiAffinity defaults to the pod's own namespace, and the cross-namespace
# subtlety belongs to q9, not here.

NAMESPACE="sched-antiaff"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment --all -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true

# Pinned by alias rather than by k3d node name so the pin survives a flavour
# change. q0 puts ck-x.io/alias=node02 on the second agent.
kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: scan-gateway
  namespace: ${NAMESPACE}
  labels:
    app: scan-gateway
spec:
  replicas: 1
  selector:
    matchLabels:
      app: scan-gateway
  template:
    metadata:
      labels:
        app: scan-gateway
    spec:
      nodeSelector:
        ck-x.io/alias: node02
      containers:
      - name: gateway
        image: nginx:1.27.4
        ports:
        - containerPort: 80
YAML

kubectl wait --for=condition=Available deployment/scan-gateway -n "$NAMESPACE" --timeout=120s || true

echo "Setup completed for Question 8"
