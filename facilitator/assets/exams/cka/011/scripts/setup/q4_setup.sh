#!/bin/bash
set -e

# Question 4: egress that has to be scoped per destination AND per port.
#
# Both servers listen on BOTH ports. That is the whole design: a policy written
# as one rule with two "to" peers and two "ports" entries reads as
# (beacon OR archive) AND (5555 OR 6666) and opens all four paths, so it passes
# the two "can reach" checks and fails the two "cannot reach" ones. The correct
# answer is two rules, each pairing one peer with one port.
#
# Probing is by Pod IP, so the question needs no DNS rule and stays about the
# rule structure. nginx is Debian-based and therefore has the bash whose
# /dev/tcp the validation probes with; the image ships no curl or wget.

NAMESPACE="net-radar"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# A previous attempt's answer must not survive into this one.
kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: two-ports
  namespace: net-radar
data:
  ports.conf: |
    server {
        listen 5555;
        location / { return 200 "port 5555\n"; }
    }
    server {
        listen 6666;
        location / { return 200 "port 6666\n"; }
    }
---
apiVersion: v1
kind: Pod
metadata:
  name: radar
  namespace: net-radar
  labels:
    app: radar
spec:
  containers:
  - name: radar
    image: nginx:1.27.4
---
apiVersion: v1
kind: Pod
metadata:
  name: beacon
  namespace: net-radar
  labels:
    app: beacon
spec:
  containers:
  - name: beacon
    image: nginx:1.27.4
    volumeMounts:
    - name: conf
      mountPath: /etc/nginx/conf.d/ports.conf
      subPath: ports.conf
  volumes:
  - name: conf
    configMap:
      name: two-ports
---
apiVersion: v1
kind: Pod
metadata:
  name: archive
  namespace: net-radar
  labels:
    app: archive
spec:
  containers:
  - name: archive
    image: nginx:1.27.4
    volumeMounts:
    - name: conf
      mountPath: /etc/nginx/conf.d/ports.conf
      subPath: ports.conf
  volumes:
  - name: conf
    configMap:
      name: two-ports
YAML

kubectl wait --for=condition=Ready pod/radar pod/beacon pod/archive -n "$NAMESPACE" --timeout=120s \
    || echo "WARNING: not every Pod in ${NAMESPACE} became ready"

echo "Setup completed for Question 4"
