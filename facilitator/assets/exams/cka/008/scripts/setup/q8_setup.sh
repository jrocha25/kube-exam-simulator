#!/bin/bash

set -e

# Question 8: two ports on one Pod, with different peers allowed on each, and a
# client set that only a matchExpressions rule can describe economically.
# nginx is given a second server block so 9090 is a real listener rather than a
# closed port that would refuse the connection for the wrong reason.

NAMESPACE="np-ports"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete pod payments frontend prometheus batch -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true
kubectl delete configmap payments-conf -n "$NAMESPACE" --ignore-not-found=true || true

kubectl apply -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: payments-conf
  namespace: ${NAMESPACE}
data:
  default.conf: |
    server {
      listen 80;
      location / { return 200 "payments-http\n"; }
    }
    server {
      listen 9090;
      location / { return 200 "payments-metrics\n"; }
    }
---
apiVersion: v1
kind: Pod
metadata:
  name: payments
  namespace: ${NAMESPACE}
  labels:
    app: payments
spec:
  containers:
  - name: web
    image: nginx:1.27.4
    ports:
    - name: http
      containerPort: 80
    - name: metrics
      containerPort: 9090
    volumeMounts:
    - name: conf
      mountPath: /etc/nginx/conf.d
  volumes:
  - name: conf
    configMap:
      name: payments-conf
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  namespace: ${NAMESPACE}
  labels:
    role: frontend
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: prometheus
  namespace: ${NAMESPACE}
  labels:
    role: monitoring
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: batch
  namespace: ${NAMESPACE}
  labels:
    role: batch
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
YAML

kubectl wait --for=condition=Ready pod/payments pod/frontend pod/prometheus pod/batch -n "$NAMESPACE" --timeout=120s || true

echo "Setup completed for Question 8"
