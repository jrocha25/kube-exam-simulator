#!/bin/bash

set -e

# Question 3: patches[].target with a labelSelector -- one patch entry that hits
# a set of resources chosen by label rather than named one at a time.
#
# Three Deployments, two of them labelled tier=backend. The third exists purely
# so the patch can be shown NOT to have touched it: a candidate who patches by
# name gets the same result on the two backends, and only the "did it stay off
# the frontend" and form checks tell the two answers apart.
#
# The images transformer is deliberately not part of this question -- cka/005 q14
# and cka/006 q12 already grade it, and this question is about target selection.

NAMESPACE="kustom-patch"
Q_DIR="/tmp/exam/q3"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment --all -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true

rm -rf "$Q_DIR"
mkdir -p "$Q_DIR/base" "$Q_DIR/overlays/prod"

for ENTRY in "route-planner:backend" "dispatch-worker:backend" "driver-portal:frontend"; do
    NAME="${ENTRY%%:*}"
    TIER="${ENTRY##*:}"
    cat > "$Q_DIR/base/${NAME}.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${NAME}
  labels:
    app: ${NAME}
    tier: ${TIER}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${NAME}
  template:
    metadata:
      labels:
        app: ${NAME}
        tier: ${TIER}
    spec:
      containers:
      - name: app
        image: nginx:1.27.4
        ports:
        - containerPort: 80
YAML
done

cat > "$Q_DIR/base/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- route-planner.yaml
- dispatch-worker.yaml
- driver-portal.yaml
YAML

( cd "$Q_DIR" && sha256sum base/* > base.sha256 )

echo "Setup completed for Question 3"
