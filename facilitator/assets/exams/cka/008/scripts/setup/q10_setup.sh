#!/bin/bash

set -e

# Question 10 (troubleshooting): the inverse symptom. 'vault-isolation' is a
# perfectly valid NetworkPolicy that the API server accepts without complaint,
# but its podSelector names app=vault-server and the Pod is labelled app=vault,
# so it selects nothing and isolates nothing. Everything still reaches vault.
#
# Relabelling the Pod would also silence the symptom, which is why the question
# forbids it and s1 checks the Pod's labels are untouched -- the Service selector
# depends on them.

NAMESPACE="np-ts-inert"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete pod vault auditor intruder -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true
kubectl delete service vault -n "$NAMESPACE" --ignore-not-found=true || true

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: vault
  namespace: ${NAMESPACE}
  labels:
    app: vault
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
  name: vault
  namespace: ${NAMESPACE}
spec:
  selector:
    app: vault
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: auditor
  namespace: ${NAMESPACE}
  labels:
    role: auditor
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: intruder
  namespace: ${NAMESPACE}
  labels:
    role: intruder
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
YAML

kubectl wait --for=condition=Ready pod/vault pod/auditor pod/intruder -n "$NAMESPACE" --timeout=120s || true

kubectl apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: vault-isolation
  namespace: ${NAMESPACE}
spec:
  podSelector:
    matchLabels:
      app: vault-server
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: auditor
    ports:
    - protocol: TCP
      port: 80
YAML

echo "Setup completed for Question 10"
