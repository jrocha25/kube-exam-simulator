#!/bin/bash
set -e

# Question 12: a second ServiceCIDR. A ClusterIP is immutable, so moving
# orbit-legacy into the new range means recreating it with an explicit address
# from that range: the allocator keeps handing out addresses from the default
# 10.96.0.0/16 for as long as it has any, so a plain recreate lands right back
# where it was. Record orbit-legacy's selector and ports for the comparison.

NAMESPACE="net-orbit"
STATE_DIR=/tmp/exam/q12

mkdir -p "$STATE_DIR"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete service orbit-gw -n "$NAMESPACE" --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orbit
  namespace: $NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: orbit
  template:
    metadata:
      labels:
        app: orbit
        lane: legacy
    spec:
      nodeSelector:
        ck-x.io/alias: node01
      containers:
      - name: web
        image: nginx:1.27.4
        ports:
        - name: http
          containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: orbit-legacy
  namespace: $NAMESPACE
spec:
  selector:
    app: orbit
    lane: legacy
  ports:
  - name: http
    port: 8080
    targetPort: http
  - name: telemetry
    port: 8125
    targetPort: 80
    protocol: TCP
---
apiVersion: v1
kind: Pod
metadata:
  name: orbit-probe
  namespace: $NAMESPACE
spec:
  nodeSelector:
    ck-x.io/alias: node01
  containers:
  - name: probe
    image: busybox:1.36
    command: ["sleep", "2147483647"]
YAML

kubectl get service orbit-legacy -n "$NAMESPACE" -o json \
    | jq -c '{selector: .spec.selector, ports: [.spec.ports[] | {name, port, targetPort, protocol}]}' \
    > "$STATE_DIR/legacy.json"

kubectl rollout status deployment/orbit -n "$NAMESPACE" --timeout=90s >/dev/null \
    || echo "WARNING: orbit did not become ready"
kubectl wait --for=condition=Ready pod/orbit-probe -n "$NAMESPACE" --timeout=90s >/dev/null \
    || echo "WARNING: orbit-probe did not become ready"

echo "Setup completed for Question 12"
