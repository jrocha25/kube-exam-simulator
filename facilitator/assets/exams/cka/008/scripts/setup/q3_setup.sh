#!/bin/bash

set -e

# Question 3: the same allow-one-hole task as question 2, but the client lives in
# another namespace, so a podSelector cannot express it. Two client namespaces --
# one carrying the label the policy must select on, one carrying nothing -- so
# that a namespaceSelector of {} (which matches every namespace) is caught.

NAMESPACE="np-crossns"
MONITOR_NS="np-crossns-monitor"
DEV_NS="np-crossns-dev"

for ns in "$NAMESPACE" "$MONITOR_NS" "$DEV_NS"; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl label namespace "$MONITOR_NS" purpose=monitoring --overwrite
kubectl label namespace "$DEV_NS" purpose- 2> /dev/null || true

kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete pod payments -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true
kubectl delete pod probe -n "$MONITOR_NS" --ignore-not-found=true --timeout=60s || true
kubectl delete pod probe -n "$DEV_NS" --ignore-not-found=true --timeout=60s || true

kubectl apply -f - <<YAML
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
    - containerPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: probe
  namespace: ${MONITOR_NS}
  labels:
    app: probe
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: probe
  namespace: ${DEV_NS}
  labels:
    app: probe
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
YAML

kubectl wait --for=condition=Ready pod/payments -n "$NAMESPACE" --timeout=120s || true
kubectl wait --for=condition=Ready pod/probe -n "$MONITOR_NS" --timeout=120s || true
kubectl wait --for=condition=Ready pod/probe -n "$DEV_NS" --timeout=120s || true

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

echo "Setup completed for Question 3"
