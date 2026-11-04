#!/bin/bash
set -e

# Question 2: an Ingress to migrate to the Gateway API. Only the CRDs and a
# GatewayClass exist -- no controller -- so the work is graded on its spec.

NAMESPACE="quay-edge"
HOST="quay.harbor.local"
CRDS=/tmp/exam-assets/scripts/setup/files/gateway-api-v1.3.0-standard-install.yaml
WORKDIR=/tmp/exam/q2

mkdir -p "$WORKDIR"

if ! kubectl apply --server-side --force-conflicts -f "$CRDS" >/dev/null; then
    echo "WARNING: could not install the Gateway API CRDs from $CRDS"
fi
kubectl wait --for=condition=Established --timeout=60s \
    crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io \
    crd/gatewayclasses.gateway.networking.k8s.io >/dev/null \
    || echo "WARNING: the Gateway API CRDs are not Established"

kubectl apply -f - <<YAML
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: harbor-gwc
spec:
  controllerName: harbor.io/edge-gateway-controller
YAML

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete gateway --all -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true
kubectl delete httproute --all -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true

openssl req -x509 -nodes -newkey rsa:2048 -days 365 \
    -keyout "$WORKDIR/tls.key" -out "$WORKDIR/tls.crt" \
    -subj "/CN=$HOST" -addext "subjectAltName=DNS:$HOST" >/dev/null 2>&1
kubectl create secret tls quay-tls -n "$NAMESPACE" \
    --cert="$WORKDIR/tls.crt" --key="$WORKDIR/tls.key" \
    --dry-run=client -o yaml | kubectl apply -f -
rm -f "$WORKDIR/tls.key"

for app in quay-web:80 quay-status:8080; do
    name=${app%%:*}
    port=${app##*:}
    kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $name
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: $name
  template:
    metadata:
      labels:
        app: $name
    spec:
      containers:
      - name: web
        image: nginx:1.27.4
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: $name
  namespace: $NAMESPACE
spec:
  selector:
    app: $name
  ports:
  - port: $port
    targetPort: 80
YAML
done

kubectl apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: quay-web
  namespace: $NAMESPACE
spec:
  ingressClassName: harbor-legacy
  tls:
  - hosts:
    - $HOST
    secretName: quay-tls
  rules:
  - host: $HOST
    http:
      paths:
      - path: /healthz/berths
        pathType: Exact
        backend:
          service:
            name: quay-status
            port:
              number: 8080
      - path: /
        pathType: Prefix
        backend:
          service:
            name: quay-web
            port:
              number: 80
YAML

echo "Setup for question 2 completed"
