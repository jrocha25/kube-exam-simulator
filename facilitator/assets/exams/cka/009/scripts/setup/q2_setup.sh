#!/bin/bash

set -e

# Question 2: generators, and the one case where the name-suffix hash has to go.
#
# The honest justification matters here. Kustomize's name-reference transformer
# rewrites configMapRef/secretRef names to the hashed name automatically, so a
# hash does NOT break a reference inside the same kustomization -- a question
# claiming otherwise would be teaching a falsehood. The real reason to disable it
# is a consumer OUTSIDE the kustomization that reads the object by exact name,
# which is how the question is framed.
#
# cka/005 q14 proves generator use BY the hash suffix. That evidence is gone once
# the hash is off, so the validation proves provenance two other ways: the name
# carries no suffix, and configMapGenerator actually appears in the overlay.

NAMESPACE="kustom-gen"
Q_DIR="/tmp/exam/q2"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment,configmap,secret --all -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true

rm -rf "$Q_DIR"
mkdir -p "$Q_DIR/base" "$Q_DIR/overlays/prod"

cat > "$Q_DIR/base/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: depot-config
  labels:
    app: depot-config
spec:
  replicas: 1
  selector:
    matchLabels:
      app: depot-config
  template:
    metadata:
      labels:
        app: depot-config
    spec:
      containers:
      - name: app
        image: nginx:1.27.4
        envFrom:
        - configMapRef:
            name: app-settings
YAML

cat > "$Q_DIR/base/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
YAML

# The certificate the secretGenerator has to read. Its content is random per
# attempt: a validation script that compared against a fixed string would be
# grading typing, and a candidate could satisfy it with an inline literal
# instead of reading the file.
CA_TOKEN=$(tr -dc 'a-f0-9' < /dev/urandom 2> /dev/null | head -c 48 || echo "fallbackfallbackfallbackfallbackfallbackfallb")

cat > "$Q_DIR/overlays/prod/depot-ca.pem" <<YAML
-----BEGIN CERTIFICATE-----
${CA_TOKEN}
-----END CERTIFICATE-----
YAML

echo "Setup completed for Question 2"
