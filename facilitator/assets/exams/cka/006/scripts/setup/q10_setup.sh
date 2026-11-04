#!/bin/bash
set -e

# Question 10: an egress policy that is too tight. billing is supposed to reach
# the invoice service and nothing else; the policy that enforces that names the
# wrong peer (app=archive, the service billing must NOT reach), so billing can
# talk to precisely the one thing it should not and nothing it should.
#
# The fix has to stay inside the shape the policy already has: deleting it or
# adding a blanket allow would "work" and teaches the opposite lesson, so the
# question forbids both and a verification step checks for it.
#
# Deliberately about a port/peer, not DNS. Question 8's DNS outage is staged on the
# auxiliary cluster now, so resolution here is healthy -- but grading a policy by a
# name lookup would still be testing two things at once, and only one of them is
# the policy.

NAMESPACE="net-billing"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true
kubectl delete pod,service --all -n "$NAMESPACE" --ignore-not-found=true --wait=false

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: billing
  namespace: $NAMESPACE
  labels:
    app: billing
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
  name: invoice
  namespace: $NAMESPACE
  labels:
    app: invoice
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
  name: archive
  namespace: $NAMESPACE
  labels:
    app: archive
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
kind: Service
metadata:
  name: invoice
  namespace: $NAMESPACE
spec:
  selector:
    app: invoice
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
YAML

kubectl wait --for=condition=Ready pod --all -n "$NAMESPACE" --timeout=180s \
    || echo "WARNING: not every pod in $NAMESPACE became ready"

kubectl apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: billing-egress
  namespace: $NAMESPACE
spec:
  podSelector:
    matchLabels:
      app: billing
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: archive
    ports:
    - protocol: TCP
      port: 80
YAML

echo "Setup completed for Question 10"
