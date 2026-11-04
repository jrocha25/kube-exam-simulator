#!/bin/bash
set -e

# Question 8: the per-Pod A record a headless Service publishes.
#
# A headless Service is what makes station-index-0.station-index... resolvable at
# all: a ClusterIP Service publishes only its own name. The provenance check at
# validation time needs the answer to be unguessable, and a Pod IP is -- it
# changes on every warm-up.
#
# busybox is the client because its nslookup is the tool the exam expects, and
# the question gives the name with a trailing dot: busybox's nslookup queries the
# name exactly as given and ignores the search list.

NAMESPACE="dns-station"
DIR="/tmp/exam/q8"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

mkdir -p "$DIR"
rm -f "${DIR}/lookup.txt"

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: station-index
  namespace: dns-station
spec:
  clusterIP: None
  selector:
    app: station-index
  ports:
  - protocol: TCP
    port: 80
    name: web
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: station-index
  namespace: dns-station
spec:
  serviceName: station-index
  replicas: 2
  selector:
    matchLabels:
      app: station-index
  template:
    metadata:
      labels:
        app: station-index
    spec:
      containers:
      - name: index
        image: nginx:1.27.4
        ports:
        - name: web
          containerPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: dns-tool
  namespace: dns-station
  labels:
    app: dns-tool
spec:
  containers:
  - name: tool
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
YAML

kubectl rollout status statefulset/station-index -n "$NAMESPACE" --timeout=150s \
    || echo "WARNING: the station-index StatefulSet did not become ready"
kubectl wait --for=condition=Ready pod/dns-tool -n "$NAMESPACE" --timeout=120s \
    || echo "WARNING: the dns-tool Pod did not become ready"

echo "Setup completed for Question 8"
