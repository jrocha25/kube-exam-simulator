#!/bin/bash
set -e

# Question 7: one protected Pod, one client that must keep working, one client in
# an unlabelled namespace and one neighbour in the same namespace that must both
# be shut out. Bare Pods, not Deployments, so the validation can look their IPs up
# by name.
for ns in net-tier net-tier-clients net-tier-others; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl label namespace net-tier-clients team=trusted --overwrite
kubectl label namespace net-tier-others team- 2>/dev/null || true

kubectl delete networkpolicy --all -n net-tier --ignore-not-found=true
kubectl delete pod payments neighbour -n net-tier --ignore-not-found=true --timeout=60s || true
kubectl delete pod client-allowed -n net-tier-clients --ignore-not-found=true --timeout=60s || true
kubectl delete pod client-denied -n net-tier-others --ignore-not-found=true --timeout=60s || true

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: payments
  namespace: net-tier
  labels:
    app: payments
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
  name: neighbour
  namespace: net-tier
  labels:
    app: neighbour
spec:
  containers:
  - name: probe
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: client-allowed
  namespace: net-tier-clients
  labels:
    app: client
spec:
  containers:
  - name: probe
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: client-denied
  namespace: net-tier-others
  labels:
    app: client
spec:
  containers:
  - name: probe
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
YAML

kubectl wait --for=condition=Ready pod/payments pod/neighbour -n net-tier --timeout=120s || true
kubectl wait --for=condition=Ready pod/client-allowed -n net-tier-clients --timeout=120s || true
kubectl wait --for=condition=Ready pod/client-denied -n net-tier-others --timeout=120s || true

echo "Setup completed for Question 7"
