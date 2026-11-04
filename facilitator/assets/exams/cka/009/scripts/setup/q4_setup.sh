#!/bin/bash

set -e

# Question 4: one overlay composing two independent bases.
#
# Every Kustomize question in the repo so far builds on exactly one base. This is
# the first that has to compose, which is what makes the shared-label check
# meaningful: the transformer has to reach resources that came from two different
# directories, and a candidate who hand-edits a base only reaches one of them.
#
# The per-workload replica difference is deliberately mechanism-agnostic -- a
# patch and the replicas transformer are both fine. The graded skill is
# composition, not which knob was turned.

NAMESPACE="kustom-compose"
Q_DIR="/tmp/exam/q4"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment,service --all -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true

rm -rf "$Q_DIR"
mkdir -p "$Q_DIR/bases/app" "$Q_DIR/bases/cache" "$Q_DIR/overlays/prod"

cat > "$Q_DIR/bases/app/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: waybill-api
  labels:
    app: waybill-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: waybill-api
  template:
    metadata:
      labels:
        app: waybill-api
    spec:
      containers:
      - name: api
        image: nginx:1.27.4
        ports:
        - containerPort: 80
YAML

cat > "$Q_DIR/bases/app/service.yaml" <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: waybill-api
  labels:
    app: waybill-api
spec:
  selector:
    app: waybill-api
  ports:
  - port: 80
    targetPort: 80
YAML

cat > "$Q_DIR/bases/app/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
YAML

cat > "$Q_DIR/bases/cache/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: waybill-cache
  labels:
    app: waybill-cache
spec:
  replicas: 1
  selector:
    matchLabels:
      app: waybill-cache
  template:
    metadata:
      labels:
        app: waybill-cache
    spec:
      containers:
      - name: cache
        image: nginx:1.27.4
        ports:
        - containerPort: 80
YAML

cat > "$Q_DIR/bases/cache/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
YAML

( cd "$Q_DIR" && sha256sum bases/app/* bases/cache/* > bases.sha256 )

echo "Setup completed for Question 4"
