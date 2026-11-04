#!/bin/bash

set -e

# Question 9 (troubleshooting): the seeded policy writes namespaceSelector and
# podSelector as two separate 'from' entries -- an OR where an AND was meant --
# and the namespace label value is wrong on top of that. Net effect:
#   entry 1 matches no namespace at all (access=inventory-clients exists nowhere)
#   entry 2 matches Pods labelled app=checkout in np-ts-selector itself, of which
#           there are none
# so nothing reaches inventory and checkout is broken.
#
# 'scanner' sits in the clients namespace so that the lazy repair -- widening
# entry 1 to the whole namespace and deleting the podSelector -- is caught by
# traffic rather than by inspecting the YAML.

NAMESPACE="np-ts-selector"
CLIENT_NS="np-ts-selector-clients"

for ns in "$NAMESPACE" "$CLIENT_NS"; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl label namespace "$CLIENT_NS" access=inventory --overwrite

kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete pod inventory -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true
kubectl delete service inventory -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete deployment checkout -n "$CLIENT_NS" --ignore-not-found=true --timeout=60s || true
kubectl delete pod scanner -n "$CLIENT_NS" --ignore-not-found=true --timeout=60s || true

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: inventory
  namespace: ${NAMESPACE}
  labels:
    app: inventory
spec:
  containers:
  - name: web
    image: nginx:1.27.4
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: inventory
  namespace: ${NAMESPACE}
spec:
  selector:
    app: inventory
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout
  namespace: ${CLIENT_NS}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: checkout
  template:
    metadata:
      labels:
        app: checkout
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
  namespace: ${CLIENT_NS}
  labels:
    app: scanner
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
YAML

kubectl wait --for=condition=Ready pod/inventory -n "$NAMESPACE" --timeout=120s || true
kubectl wait --for=condition=Ready pod/scanner -n "$CLIENT_NS" --timeout=120s || true
kubectl rollout status deployment/checkout -n "$CLIENT_NS" --timeout=120s || true

kubectl apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: inventory-ingress
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: inventory
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          access: inventory-clients
    - podSelector:
        matchLabels:
          app: checkout
    ports:
    - protocol: TCP
      port: 80
YAML

echo "Setup completed for Question 9"
