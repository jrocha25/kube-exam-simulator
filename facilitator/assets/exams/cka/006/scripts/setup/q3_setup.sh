#!/bin/bash
set -e

# Question 3: nothing to break. The namespace and a workload to read exist so the
# candidate has something to test the new credential against, and so the
# permission checks have a real object to resolve.

NAMESPACE="dev-team"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete csr mira-access --ignore-not-found=true
kubectl delete role,rolebinding --all -n "$NAMESPACE" --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: dev-portal
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: dev-portal
  template:
    metadata:
      labels:
        app: dev-portal
    spec:
      containers:
      - name: portal
        image: nginx:1.27.4
        ports:
        - containerPort: 80
YAML

rm -rf /tmp/exam/q3
mkdir -p /tmp/exam/q3

echo "Setup completed for Question 3"
