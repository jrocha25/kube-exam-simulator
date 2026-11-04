#!/bin/bash

set -e

# Question 12: the capstone. Placement policy delivered through Kustomize.
#
# The base is a plain Deployment with no scheduling rules and is off limits, so
# the anti-affinity, the spread constraint and the replica count all have to
# arrive from the overlay. That is the real-world shape -- the application team
# owns the base, the platform team owns where it runs -- and it is the only
# question in the lab where the classic self anti-affinity rule appears. The
# novelty here is the delivery mechanism, not the rule.

NAMESPACE="kustom-sched"
Q_DIR="/tmp/exam/q12"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment --all -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true

rm -rf "$Q_DIR"
mkdir -p "$Q_DIR/base" "$Q_DIR/overlays/prod"

cat > "$Q_DIR/base/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: freight-api
  labels:
    app: freight-api
spec:
  replicas: 1
  selector:
    matchLabels:
      app: freight-api
  template:
    metadata:
      labels:
        app: freight-api
    spec:
      containers:
      - name: api
        image: nginx:1.27.4
        ports:
        - containerPort: 80
YAML

cat > "$Q_DIR/base/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
YAML

( cd "$Q_DIR" && sha256sum base/* > base.sha256 )

echo "Setup completed for Question 12"
