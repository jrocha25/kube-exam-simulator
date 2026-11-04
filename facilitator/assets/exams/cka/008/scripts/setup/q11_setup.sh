#!/bin/bash

set -e

# Question 11 (troubleshooting): the server side is already correct. archive-ingress
# admits the whole np-ts-egress namespace on port 80, so a candidate who reads only
# the archive namespace finds nothing wrong. The block is on the client side, in a
# default-deny-egress that the question does not point at.
#
# The decoy namespace exists so that the shortcut fix -- allowing all egress, or
# egress to 0.0.0.0/0 -- is caught by traffic.

NAMESPACE="np-ts-egress"
STORE_NS="np-ts-egress-store"
DECOY_NS="np-ts-egress-decoy"

for ns in "$NAMESPACE" "$STORE_NS" "$DECOY_NS"; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl label namespace "$STORE_NS" role=store --overwrite

kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete networkpolicy --all -n "$STORE_NS" --ignore-not-found=true || true
kubectl delete pod sync-agent -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true
kubectl delete pod archive -n "$STORE_NS" --ignore-not-found=true --timeout=60s || true
kubectl delete service archive -n "$STORE_NS" --ignore-not-found=true || true
kubectl delete pod secrets-api -n "$DECOY_NS" --ignore-not-found=true --timeout=60s || true
kubectl delete service secrets-api -n "$DECOY_NS" --ignore-not-found=true || true

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: sync-agent
  namespace: ${NAMESPACE}
  labels:
    app: sync-agent
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: archive
  namespace: ${STORE_NS}
  labels:
    app: archive
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
  name: archive
  namespace: ${STORE_NS}
spec:
  selector:
    app: archive
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: secrets-api
  namespace: ${DECOY_NS}
  labels:
    app: secrets-api
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
  name: secrets-api
  namespace: ${DECOY_NS}
spec:
  selector:
    app: secrets-api
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
YAML

kubectl wait --for=condition=Ready pod/sync-agent -n "$NAMESPACE" --timeout=120s || true
kubectl wait --for=condition=Ready pod/archive -n "$STORE_NS" --timeout=120s || true
kubectl wait --for=condition=Ready pod/secrets-api -n "$DECOY_NS" --timeout=120s || true

kubectl apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: archive-ingress
  namespace: ${STORE_NS}
spec:
  podSelector:
    matchLabels:
      app: archive
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ${NAMESPACE}
    ports:
    - protocol: TCP
      port: 80
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: ${NAMESPACE}
spec:
  podSelector: {}
  policyTypes:
  - Egress
YAML

echo "Setup completed for Question 11"
