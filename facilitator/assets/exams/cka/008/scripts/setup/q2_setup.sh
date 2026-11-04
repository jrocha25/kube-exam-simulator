#!/bin/bash

set -e

# Question 2: a namespace that is already default-denied, so the candidate's job
# is purely to punch one hole through it. 'scanner' exists to prove the hole is
# the right shape and no wider.

NAMESPACE="np-tiers"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete pod api frontend scanner -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: api
  namespace: ${NAMESPACE}
  labels:
    app: api
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
  name: scanner
  namespace: ${NAMESPACE}
  labels:
    role: scanner
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
YAML

kubectl wait --for=condition=Ready pod/api pod/frontend pod/scanner -n "$NAMESPACE" --timeout=120s || true

# The default-deny is seeded, not asked for -- question 1 already graded that
# skill, and this question is about the allow rule.
kubectl apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: ${NAMESPACE}
spec:
  podSelector: {}
  policyTypes:
  - Ingress
YAML

echo "Setup completed for Question 2"
