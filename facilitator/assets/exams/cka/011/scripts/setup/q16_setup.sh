#!/bin/bash
set -e

# Question 16: raise a workload from BestEffort to Guaranteed.
#
# The Deployment is staged with no resources block at all, which is what makes
# its Pods BestEffort. Guaranteed needs limits equal to requests on every
# container, so an answer that sets only limits (which defaults requests to the
# limits) also passes -- that is correct Kubernetes and the check grades
# status.qosClass rather than a particular way of writing it.

NAMESPACE="qos-hangar"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hangar-ops
  namespace: $NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: hangar-ops
  template:
    metadata:
      labels:
        app: hangar-ops
    spec:
      containers:
      - name: ops
        image: nginx:1.27.4
YAML

# Undo a previous attempt: strip any resources the candidate added last time.
kubectl patch deployment hangar-ops -n "$NAMESPACE" --type=json \
    -p '[{"op":"replace","path":"/spec/template/spec/containers/0/resources","value":{}}]' \
    >/dev/null 2>&1 || true

kubectl rollout status deployment/hangar-ops -n "$NAMESPACE" --timeout=120s \
    || echo "WARNING: the hangar-ops Deployment did not become ready"

echo "Setup completed for Question 16"
