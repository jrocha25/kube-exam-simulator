#!/bin/bash
set -e

# Question 4: Pods with a deliberately uneven mix of memory limits. "search-api"
# declares none at all and is the one the candidate has to bring under the new
# namespace policy.
kubectl create namespace registry-audit --dry-run=client -o yaml | kubectl apply -f -

# Drop any LimitRange left by a previous attempt BEFORE recreating the Pods:
# otherwise search-api would be admitted with a defaulted limit and the question
# would start out already solved.
kubectl delete limitrange audit-defaults -n registry-audit --ignore-not-found=true

for pod in orders-api billing-api search-api mail-api; do
    kubectl delete pod "$pod" -n registry-audit --ignore-not-found=true --timeout=60s || true
done

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: orders-api
  namespace: registry-audit
spec:
  containers:
  - name: api
    image: nginx:1.27.4
    resources:
      requests:
        memory: 32Mi
      limits:
        memory: 128Mi
  - name: sidecar
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
    resources:
      requests:
        memory: 16Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: billing-api
  namespace: registry-audit
spec:
  containers:
  - name: api
    image: nginx:1.27.4
    resources:
      requests:
        memory: 64Mi
      limits:
        memory: 256Mi
---
apiVersion: v1
kind: Pod
metadata:
  name: search-api
  namespace: registry-audit
spec:
  containers:
  - name: api
    image: nginx:1.27.4
---
apiVersion: v1
kind: Pod
metadata:
  name: mail-api
  namespace: registry-audit
spec:
  containers:
  - name: api
    image: alpine:3.20
    command: ["sh", "-c", "sleep 86400"]
    resources:
      requests:
        memory: 16Mi
      limits:
        memory: 64Mi
YAML

for pod in orders-api billing-api search-api mail-api; do
    kubectl wait --for=condition=Ready "pod/$pod" -n registry-audit --timeout=120s || true
done

echo "Setup completed for Question 4"
