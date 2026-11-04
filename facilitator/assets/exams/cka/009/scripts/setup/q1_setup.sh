#!/bin/bash

set -e

# Question 1: the gentlest Kustomize task in the lab. The base is complete and
# correct; the whole job is a first overlay.
#
# It grades nameSuffix and commonAnnotations, which no existing lab uses --
# cka/002, cka/005 and cka/006 all reach for namePrefix and the labels
# transformer. The Service is in the base specifically so the annotation check
# has two resources to look at: a candidate who annotates the Deployment by hand
# instead of using the transformer gets one of them and fails.

NAMESPACE="kustom-intro"
Q_DIR="/tmp/exam/q1"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment,service --all -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true

rm -rf "$Q_DIR"
mkdir -p "$Q_DIR/base" "$Q_DIR/overlays/dev"

cat > "$Q_DIR/base/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: parcel-index
  labels:
    app: parcel-index
spec:
  replicas: 2
  selector:
    matchLabels:
      app: parcel-index
  template:
    metadata:
      labels:
        app: parcel-index
    spec:
      containers:
      - name: web
        image: nginx:1.27.4
        ports:
        - containerPort: 80
YAML

cat > "$Q_DIR/base/service.yaml" <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: parcel-index
  labels:
    app: parcel-index
spec:
  selector:
    app: parcel-index
  ports:
  - port: 80
    targetPort: 80
YAML

cat > "$Q_DIR/base/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
YAML

# Recorded so the "base untouched" check can be a checksum rather than a guess,
# the way cka/005 q15 does it.
( cd "$Q_DIR" && sha256sum base/* > base.sha256 )

echo "Setup completed for Question 1"
