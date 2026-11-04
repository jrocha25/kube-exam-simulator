#!/bin/bash
set -e

# Question 3: a small, deterministic set of Pods to extract data from.
# "flaky-sync" exits non-zero on purpose so exactly one Pod in the namespace
# accumulates restarts -- the answer to the restart question is never a tie.
kubectl create namespace insight --dry-run=client -o yaml | kubectl apply -f -

for pod in web-front queue-worker log-shipper flaky-sync; do
    kubectl delete pod "$pod" -n insight --ignore-not-found=true --timeout=60s || true
done

mkdir -p /tmp/exam/q3
rm -f /tmp/exam/q3/restarts.txt /tmp/exam/q3/nodes.txt

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: web-front
  namespace: insight
  labels:
    app: web-front
spec:
  containers:
  - name: web
    image: nginx:1.27.4
---
apiVersion: v1
kind: Pod
metadata:
  name: queue-worker
  namespace: insight
  labels:
    app: queue-worker
spec:
  containers:
  - name: worker
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: log-shipper
  namespace: insight
  labels:
    app: log-shipper
spec:
  containers:
  - name: shipper
    image: alpine:3.20
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: flaky-sync
  namespace: insight
  labels:
    app: flaky-sync
spec:
  restartPolicy: Always
  containers:
  - name: sync
    image: busybox:1.36
    command: ["sh", "-c", "sleep 5; exit 1"]
YAML

# Only the three long lived Pods need to be up; flaky-sync is supposed to be
# restarting, so waiting on it would never return.
for pod in web-front queue-worker log-shipper; do
    kubectl wait --for=condition=Ready "pod/$pod" -n insight --timeout=120s || true
done

echo "Setup completed for Question 3"
