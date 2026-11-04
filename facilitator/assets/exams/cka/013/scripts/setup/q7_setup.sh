#!/bin/bash
set -e

# Question 7: an HPA with a behavior block, delivered through a Kustomize
# overlay. The overlay's namePrefix renames the Deployment to prod-tide-reader;
# Kustomize rewrites an HPA's scaleTargetRef along with it, so the candidate can
# write the base name. The base is fingerprinted to catch an HPA added there.

NAMESPACE="wl-tide-prod"
DIR=/tmp/exam/q7/tidereader

rm -rf "$DIR"
mkdir -p "$DIR/base" "$DIR/overlays/prod"

cat > "$DIR/base/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tide-reader
  labels:
    app: tide-reader
spec:
  replicas: 2
  selector:
    matchLabels:
      app: tide-reader
  template:
    metadata:
      labels:
        app: tide-reader
    spec:
      nodeSelector:
        ck-x.io/alias: node01
      containers:
      - name: reader
        image: nginx:1.27.4
        resources:
          requests:
            cpu: 50m
            memory: 32Mi
          limits:
            cpu: 200m
            memory: 64Mi
YAML

cat > "$DIR/base/service.yaml" <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: tide-reader
spec:
  selector:
    app: tide-reader
  ports:
  - port: 80
    targetPort: 80
YAML

cat > "$DIR/base/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
YAML

cat > "$DIR/overlays/prod/kustomization.yaml" <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: $NAMESPACE
namePrefix: prod-
labels:
- pairs:
    env: prod
resources:
- ../../base
YAML

(cd "$DIR" && find base -type f | sort | xargs sha256sum) > /tmp/exam/q7/.base.sha256

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -k "$DIR/overlays/prod" || echo "WARNING: the prod overlay did not apply"

echo "Setup completed for Question 7"
