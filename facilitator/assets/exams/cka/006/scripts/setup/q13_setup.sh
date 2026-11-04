#!/bin/bash
set -e

# Question 13: a base that already exists, so the marks are entirely in the
# overlay's transformers -- a strategic merge patch, a JSON 6902 patch and a
# secretGenerator. The base is shared and must not be edited, which is what makes
# a patch the only available answer.

NAMESPACE="kustom-stage"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment,service,secret --all -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true

rm -rf /tmp/exam/q13
mkdir -p /tmp/exam/q13/base /tmp/exam/q13/overlays/staging

cat > /tmp/exam/q13/base/deployment.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: nginx:1.27.4
        ports:
        - containerPort: 80
        env:
        - name: LOG_LEVEL
          value: info
YAML

cat > /tmp/exam/q13/base/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
YAML

echo "Setup completed for Question 13"
