#!/bin/bash
set -e

# Question 5: the same lesson as question 4, but staged as a fault to find.
#
# apron-egress below is deliberately written the wrong way -- ONE rule carrying
# two "to" peers and two "ports" entries. Kubernetes reads that as
# (gate OR fuel) AND (7001 OR 7002), so all four paths are open and the audit
# in the question text is describing real, observable behaviour. Splitting it
# into two rules, each pairing one peer with one port, is the fix.
#
# The two "still works" checks pass on this seeded state on purpose: they are
# constraint checks worth 1 mark each, and the marks are on the two deny checks
# that only a corrected policy can satisfy.

NAMESPACE="net-apron"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: two-ports
  namespace: net-apron
data:
  ports.conf: |
    server {
        listen 7001;
        location / { return 200 "port 7001\n"; }
    }
    server {
        listen 7002;
        location / { return 200 "port 7002\n"; }
    }
---
apiVersion: v1
kind: Pod
metadata:
  name: apron
  namespace: net-apron
  labels:
    app: apron
spec:
  containers:
  - name: apron
    image: nginx:1.27.4
---
apiVersion: v1
kind: Pod
metadata:
  name: gate
  namespace: net-apron
  labels:
    app: gate
spec:
  containers:
  - name: gate
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
  name: fuel
  namespace: net-apron
  labels:
    app: fuel
spec:
  containers:
  - name: fuel
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
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: apron-egress
  namespace: net-apron
spec:
  podSelector:
    matchLabels:
      app: apron
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: gate
    - podSelector:
        matchLabels:
          app: fuel
    ports:
    - protocol: TCP
      port: 7001
    - protocol: TCP
      port: 7002
YAML

kubectl wait --for=condition=Ready pod/apron pod/gate pod/fuel -n "$NAMESPACE" --timeout=120s \
    || echo "WARNING: not every Pod in ${NAMESPACE} became ready"

echo "Setup completed for Question 5"
