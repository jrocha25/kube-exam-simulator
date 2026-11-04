#!/bin/bash
set -e

# Question 13: find a Pod's container on its node with crictl.
#
# The Pod is pinned to node01 through the ck-x.io/alias label rather than a node
# name, because kind calls its nodes cluster-worker / cluster-worker2. nginx is
# used because its entrypoint writes several lines to stdout on start, so
# "crictl logs" has something to return -- a sleeping busybox would log nothing
# and the log check would be unfalsifiable.

NAMESPACE="node-crictl"
DIR="/tmp/exam/q13"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete pod tug -n "$NAMESPACE" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true

mkdir -p "$DIR"
rm -f "${DIR}/container.txt" "${DIR}/container.log"

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: tug
  namespace: $NAMESPACE
  labels:
    app: tug
spec:
  nodeSelector:
    ck-x.io/alias: node01
  containers:
  - name: tug
    image: nginx:1.27.4
YAML

kubectl wait --for=condition=Ready pod/tug -n "$NAMESPACE" --timeout=120s \
    || echo "WARNING: the tug Pod did not become ready"

echo "Setup completed for Question 13"
