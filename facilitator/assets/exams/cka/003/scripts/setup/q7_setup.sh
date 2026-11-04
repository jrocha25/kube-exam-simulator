#!/bin/bash
set -e

# Question 7: NetworkPolicy protecting the backend pod
kubectl create namespace net-guard --dry-run=client -o yaml | kubectl apply -f -

kubectl delete networkpolicy backend-ingress -n net-guard --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: backend
  namespace: net-guard
  labels:
    app: backend
spec:
  containers:
  - name: web
    image: nginx:1.27.4
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  namespace: net-guard
  labels:
    app: frontend
spec:
  containers:
  - name: client
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: monitoring
  namespace: net-guard
  labels:
    app: monitoring
spec:
  containers:
  - name: client
    image: busybox:1.36
    command: ["sh", "-c", "sleep 3600"]
EOF

kubectl wait --for=condition=Ready pod/backend -n net-guard --timeout=180s || true
kubectl wait --for=condition=Ready pod/frontend -n net-guard --timeout=180s || true
kubectl wait --for=condition=Ready pod/monitoring -n net-guard --timeout=180s || true

echo "Setup completed for Question 7"
