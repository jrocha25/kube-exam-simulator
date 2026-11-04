#!/bin/bash
set -e

# Question 14: an overlay that will not render, carrying two independent faults:
#
#   1. resources points at "../base", which from overlays/staging resolves to
#      overlays/base -- a directory that does not exist. The overlay is two levels
#      below the base, not one.
#   2. the patch declares kind: StatefulSet while the base builds a Deployment, so
#      even once the base is found the patch matches no target.
#
# kustomize reports only the first failure it hits, so fixing one reveals the
# other rather than the whole picture at once. The image bump the question asks
# for is a third change with no seeded fault behind it: the base pins nginx:1.25
# and nothing in the overlay touches it, so the candidate has to add that
# transformer themselves.

NAMESPACE="kustom-fix"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
# The question forbids applying this overlay, and a verification step checks the
# namespace stayed empty -- so make sure a previous attempt did not leave it dirty.
kubectl delete deployment,service --all -n "$NAMESPACE" --ignore-not-found=true 2>/dev/null || true

rm -rf /tmp/exam/q14
mkdir -p /tmp/exam/q14/base /tmp/exam/q14/overlays/staging

cat > /tmp/exam/q14/base/deployment.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reports
spec:
  replicas: 1
  selector:
    matchLabels:
      app: reports
  template:
    metadata:
      labels:
        app: reports
    spec:
      containers:
      - name: reports
        image: nginx:1.25
        ports:
        - containerPort: 80
YAML

cat > /tmp/exam/q14/base/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
YAML

cat > /tmp/exam/q14/overlays/staging/replica-patch.yaml <<'YAML'
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: reports
spec:
  replicas: 4
YAML

cat > /tmp/exam/q14/overlays/staging/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- ../base
namespace: kustom-fix
patches:
- path: replica-patch.yaml
YAML

echo "Setup completed for Question 14"
