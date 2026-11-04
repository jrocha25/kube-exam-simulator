#!/bin/bash

set -e

# Question 4: the AND-versus-OR trap, staged so that traffic alone grades it.
# Three clients:
#   platform/collector -- right namespace, right Pod label   -> must reach
#   platform/auditor   -- right namespace, wrong Pod label   -> must not
#   edge/collector     -- wrong namespace, right Pod label   -> must not
# A policy written with two separate 'from' entries lets the last two through,
# so no jq inspection of the rule shape is needed.

NAMESPACE="np-combined"
PLATFORM_NS="np-combined-platform"
EDGE_NS="np-combined-edge"

for ns in "$NAMESPACE" "$PLATFORM_NS" "$EDGE_NS"; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl label namespace "$PLATFORM_NS" tier=platform --overwrite
kubectl label namespace "$EDGE_NS" tier- 2> /dev/null || true

kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete pod ledger -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true
kubectl delete pod collector auditor -n "$PLATFORM_NS" --ignore-not-found=true --timeout=60s || true
kubectl delete pod collector -n "$EDGE_NS" --ignore-not-found=true --timeout=60s || true

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: ledger
  namespace: ${NAMESPACE}
  labels:
    app: ledger
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
  name: collector
  namespace: ${PLATFORM_NS}
  labels:
    app: collector
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: auditor
  namespace: ${PLATFORM_NS}
  labels:
    app: auditor
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: collector
  namespace: ${EDGE_NS}
  labels:
    app: collector
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
YAML

kubectl wait --for=condition=Ready pod/ledger -n "$NAMESPACE" --timeout=120s || true
kubectl wait --for=condition=Ready pod/collector pod/auditor -n "$PLATFORM_NS" --timeout=120s || true
kubectl wait --for=condition=Ready pod/collector -n "$EDGE_NS" --timeout=120s || true

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

echo "Setup completed for Question 4"
