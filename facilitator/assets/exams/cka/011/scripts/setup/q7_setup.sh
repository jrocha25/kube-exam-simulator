#!/bin/bash
set -e

# Question 7: Pod-level DNS configuration.
#
# The Service the candidate has to reach lives in a SECOND namespace, so a bare
# short name cannot resolve without a search domain being added to the Pod. That
# namespace is read-only for the question, which keeps the one-namespace-per-
# question rule that makes concurrent validation safe.

NAMESPACE="dns-apron"
WX_NAMESPACE="dns-apron-wx"

for ns in "$NAMESPACE" "$WX_NAMESPACE"; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

# A previous attempt's Pod would carry a stale spec.
kubectl delete pod briefing -n "$NAMESPACE" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wx-feed
  namespace: $WX_NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wx-feed
  template:
    metadata:
      labels:
        app: wx-feed
    spec:
      containers:
      - name: wx-feed
        image: nginx:1.27.4
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: wx-feed
  namespace: $WX_NAMESPACE
spec:
  selector:
    app: wx-feed
  ports:
  - port: 80
    targetPort: 80
YAML

kubectl rollout status deployment/wx-feed -n "$WX_NAMESPACE" --timeout=120s \
    || echo "WARNING: the wx-feed Deployment did not become ready"

echo "Setup completed for Question 7"
