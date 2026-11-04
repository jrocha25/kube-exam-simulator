#!/bin/bash
set -e

# Question 6: namespace guardrails. manifest-api starts as a typical workload
# that predates them -- busybox, running as root, no securityContext and no
# resources. Pod Security admission and quotas are checked only when a Pod is
# admitted, so labelling the namespace changes nothing about the running Pods;
# the candidate has to get them re-admitted, which means making the template
# pass "restricted" (non-root user, no privilege escalation, all capabilities
# dropped, RuntimeDefault seccomp). Record the current ReplicaSet so the
# validation can tell re-admitted Pods from the originals.

NAMESPACE="wl-harbor"
DEPLOYMENT="manifest-api"
STATE_DIR=/tmp/exam/q6

mkdir -p "$STATE_DIR"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT
  namespace: $NAMESPACE
  labels:
    app: $DEPLOYMENT
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
      nodeSelector:
        ck-x.io/alias: node01
      containers:
      - name: api
        image: busybox:1.36
        command: ["sh", "-c", "while true; do echo manifest-api heartbeat; sleep 30; done"]
YAML

kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=90s \
    || echo "WARNING: $DEPLOYMENT did not become ready"

kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" \
    -o jsonpath='{.items[0].metadata.labels.pod-template-hash}' > "$STATE_DIR/template-hash" \
    || echo "WARNING: could not record the original ReplicaSet"

echo "Setup completed for Question 6"
