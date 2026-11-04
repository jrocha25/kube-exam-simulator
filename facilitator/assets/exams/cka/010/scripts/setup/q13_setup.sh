#!/bin/bash
set -e

# Question 13: a legacy hostname that has to resolve to an in-cluster Service.
# Stages the Service (with a real backend, so it has a stable cluster IP and
# endpoints) and the busybox Pod the candidate and the validation resolve from.
# The CoreDNS configuration is left exactly as kubeadm wrote it; a previous
# attempt's rewrite is removed so a stale answer does not pass on its own.

NAMESPACE="dns-alias"
ALIAS="ledger.corp.internal"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete pod --all -n "$NAMESPACE" --ignore-not-found=true --wait=false

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ledger
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ledger
  template:
    metadata:
      labels:
        app: ledger
    spec:
      containers:
      - name: ledger
        image: nginx:1.27.4
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: ledger
  namespace: $NAMESPACE
spec:
  selector:
    app: ledger
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: resolver
  namespace: $NAMESPACE
spec:
  containers:
  - name: resolver
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
YAML

# Undo a previous attempt's answer, if the Corefile still carries it.
if kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' 2>/dev/null | grep -q "$ALIAS"; then
    echo "removing a leftover ${ALIAS} rule from the Corefile"
    kubectl get configmap coredns -n kube-system -o json \
        | jq --arg a "$ALIAS" '.data.Corefile |= (split("\n") | map(select(contains($a) | not)) | join("\n"))' \
        | kubectl apply -f - >/dev/null
    kubectl rollout restart deployment/coredns -n kube-system >/dev/null
fi

kubectl wait --for=condition=Ready pod/resolver -n "$NAMESPACE" --timeout=120s \
    || echo "WARNING: the resolver pod did not become ready"

echo "Setup completed for Question 13"
