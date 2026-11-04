#!/bin/bash
set -e

# Question 17: what kube-proxy does on a node when a Service appears.
# Only the backing Pod is staged; creating the Service is the candidate's job,
# and it is the Service's live cluster IP that the captured rules are checked
# against.

NAMESPACE="svc-iptables"
DIR="/tmp/exam/q17"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete service apronctl -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true

mkdir -p "$DIR"
rm -f "${DIR}/rules.txt"

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: apronctl
  namespace: $NAMESPACE
  labels:
    app: apronctl
spec:
  containers:
  - name: apronctl
    image: nginx:1.27.4
    ports:
    - containerPort: 80
YAML

kubectl wait --for=condition=Ready pod/apronctl -n "$NAMESPACE" --timeout=120s \
    || echo "WARNING: the apronctl Pod did not become ready"

echo "Setup completed for Question 17"
