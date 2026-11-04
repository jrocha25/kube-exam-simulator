#!/bin/bash

set -e

# Question 7: policies are additive. 'allow-frontend' is seeded as though another
# team owns it, and it is the thing that isolates 'reports' in the first place --
# so 'backup' is already shut out before the candidate touches anything. The only
# correct move is a second policy; editing the first is explicitly forbidden and
# is checked.

NAMESPACE="np-additive"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete pod reports frontend backup -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: reports
  namespace: ${NAMESPACE}
  labels:
    app: reports
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
  name: backup
  namespace: ${NAMESPACE}
  labels:
    role: backup
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
YAML

kubectl wait --for=condition=Ready pod/reports pod/frontend pod/backup -n "$NAMESPACE" --timeout=120s || true

kubectl apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: reports
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: frontend
    ports:
    - protocol: TCP
      port: 80
YAML

echo "Setup completed for Question 7"
