#!/bin/bash
set -e

# Question 9: NetworkPolicy with both policyTypes. Three pods in net-orders' own
# namespace plus a backend in another, so the candidate has to write an ingress
# rule that admits exactly one peer and an egress rule that permits the backend
# *and* DNS -- the moment Egress appears in policyTypes, everything not named is
# denied, including name resolution.

NAMESPACE="net-orders"
BACKEND_NS="net-ledger"

for ns in "$NAMESPACE" "$BACKEND_NS"; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl label namespace "$BACKEND_NS" tier=ledger --overwrite >/dev/null
kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true
kubectl delete pod,service --all -n "$NAMESPACE" --ignore-not-found=true --wait=false
kubectl delete pod,service --all -n "$BACKEND_NS" --ignore-not-found=true --wait=false

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: orders
  namespace: $NAMESPACE
  labels:
    app: orders
spec:
  # Pinned to node01 so that node02 carries nothing but controller-managed
  # workloads: question 5 drains node02, and "kubectl drain" refuses to evict a
  # Pod that no controller owns. These Pods request no resources, so the reduced
  # Allocatable that question 2 stages on node01 does not affect them.
  nodeSelector:
    ck-x.io/alias: node01
  containers:
  - name: web
    image: nginx:1.27.4
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: gateway
  namespace: $NAMESPACE
  labels:
    app: gateway
spec:
  # Pinned to node01 so that node02 carries nothing but controller-managed
  # workloads: question 5 drains node02, and "kubectl drain" refuses to evict a
  # Pod that no controller owns. These Pods request no resources, so the reduced
  # Allocatable that question 2 stages on node01 does not affect them.
  nodeSelector:
    ck-x.io/alias: node01
  containers:
  - name: client
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: reporting
  namespace: $NAMESPACE
  labels:
    app: reporting
spec:
  # Pinned to node01 so that node02 carries nothing but controller-managed
  # workloads: question 5 drains node02, and "kubectl drain" refuses to evict a
  # Pod that no controller owns. These Pods request no resources, so the reduced
  # Allocatable that question 2 stages on node01 does not affect them.
  nodeSelector:
    ck-x.io/alias: node01
  containers:
  - name: client
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: ledger
  namespace: $BACKEND_NS
  labels:
    app: ledger
spec:
  # Pinned to node01 so that node02 carries nothing but controller-managed
  # workloads: question 5 drains node02, and "kubectl drain" refuses to evict a
  # Pod that no controller owns. These Pods request no resources, so the reduced
  # Allocatable that question 2 stages on node01 does not affect them.
  nodeSelector:
    ck-x.io/alias: node01
  containers:
  - name: web
    image: nginx:1.27.4
    ports:
    - containerPort: 80
YAML

kubectl wait --for=condition=Ready pod --all -n "$NAMESPACE" --timeout=180s \
    || echo "WARNING: not every pod in $NAMESPACE became ready"
kubectl wait --for=condition=Ready pod/ledger -n "$BACKEND_NS" --timeout=180s \
    || echo "WARNING: the ledger pod did not become ready"

echo "Setup completed for Question 9"
