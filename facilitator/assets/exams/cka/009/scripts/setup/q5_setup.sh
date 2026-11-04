#!/bin/bash

set -e

# Question 5: a broken overlay carrying two faults of deliberately different
# character. Neither is reused from cka/005 q15 or cka/006 q14, which between
# them already stage a resources path resolving one level short, a patch whose
# kind disagrees with the base, and a patch whose metadata.name disagrees.
#
#   LOUD   configMapGenerator with "behavior: merge" naming a ConfigMap that no
#          base declares. kustomize refuses to build at all. This is the stated
#          symptom.
#
#   SILENT a strategic merge patch whose metadata.name matches, but whose
#          container name does not. Container lists are merged by the "name" key,
#          so kustomize APPENDS a second container rather than editing the first.
#          The build succeeds and the output is simply wrong -- and because both
#          containers then try to bind port 80, the applied Deployment never
#          becomes ready. The question describes only the end state, never the
#          fault.
#
# This one is applied rather than rendered-only, which is the other thing that
# sets it apart from the two existing broken-overlay questions.

NAMESPACE="kustom-repair"
Q_DIR="/tmp/exam/q5"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment,configmap --all -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true

rm -rf "$Q_DIR"
mkdir -p "$Q_DIR/base" "$Q_DIR/overlays/staging"

cat > "$Q_DIR/base/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: customs-check
  labels:
    app: customs-check
spec:
  replicas: 1
  selector:
    matchLabels:
      app: customs-check
  template:
    metadata:
      labels:
        app: customs-check
    spec:
      containers:
      - name: checker
        image: nginx:1.25
        ports:
        - containerPort: 80
YAML

cat > "$Q_DIR/base/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
YAML

# FAULT 1 (loud): behavior "merge" against a ConfigMap the base never declares.
cat > "$Q_DIR/overlays/staging/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kustom-repair
resources:
- ../../base
configMapGenerator:
- name: checker-settings
  behavior: merge
  literals:
  - MODE=strict
patches:
- path: container-patch.yaml
- path: replica-patch.yaml
YAML

# FAULT 2 (silent): the base's container is called "checker", not "check".
cat > "$Q_DIR/overlays/staging/container-patch.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: customs-check
spec:
  template:
    spec:
      containers:
      - name: check
        image: nginx:1.27.4
YAML

# Correct as it stands. It is named in the question so the candidate knows it is
# not the thing to delete.
cat > "$Q_DIR/overlays/staging/replica-patch.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: customs-check
spec:
  replicas: 4
YAML

( cd "$Q_DIR" && sha256sum base/* > base.sha256 )

echo "Setup completed for Question 5"
