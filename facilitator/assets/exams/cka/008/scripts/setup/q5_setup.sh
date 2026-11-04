#!/bin/bash

set -e

# Question 5: the first egress question. 'orders' is a busybox so it can run
# wget and nslookup; catalog and reports are nginx behind Services so that the
# allowed path can be graded by name (which only works once DNS egress is open)
# and the denied path by IP (which stays denied regardless of DNS).

NAMESPACE="np-egress"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete pod orders catalog reports -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true
kubectl delete service catalog reports -n "$NAMESPACE" --ignore-not-found=true || true

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: orders
  namespace: ${NAMESPACE}
  labels:
    app: orders
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: catalog
  namespace: ${NAMESPACE}
  labels:
    app: catalog
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
kind: Service
metadata:
  name: catalog
  namespace: ${NAMESPACE}
spec:
  selector:
    app: catalog
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: reports
  namespace: ${NAMESPACE}
spec:
  selector:
    app: reports
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
YAML

kubectl wait --for=condition=Ready pod/orders pod/catalog pod/reports -n "$NAMESPACE" --timeout=120s || true

echo "Setup completed for Question 5"
