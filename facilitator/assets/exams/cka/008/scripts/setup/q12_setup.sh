#!/bin/bash

set -e

# Question 12: the design finale. Three tiers in one namespace plus two clients
# next door, and no policies at all -- everything the matrix asks for is the
# candidate's to build.
#
# api and db are nginx with an extra server block so 8080 and 5432 are real
# listeners; a closed port would refuse the connection and make a denied probe
# pass for the wrong reason. web and api are nginx (Debian, so bash and /dev/tcp
# are available) because they have to originate traffic as well as receive it;
# the two clients are busybox and use wget.

NAMESPACE="np-design"
CLIENT_NS="np-design-clients"

for ns in "$NAMESPACE" "$CLIENT_NS"; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl label namespace "$CLIENT_NS" role=edge --overwrite

kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete pod web api db -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true
kubectl delete service web api db -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete configmap api-conf db-conf -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete pod ingress-gw rogue -n "$CLIENT_NS" --ignore-not-found=true --timeout=60s || true

kubectl apply -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: api-conf
  namespace: ${NAMESPACE}
data:
  default.conf: |
    server {
      listen 8080;
      location / { return 200 "api\n"; }
    }
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: db-conf
  namespace: ${NAMESPACE}
data:
  default.conf: |
    server {
      listen 5432;
      location / { return 200 "db\n"; }
    }
---
apiVersion: v1
kind: Pod
metadata:
  name: web
  namespace: ${NAMESPACE}
  labels:
    tier: web
spec:
  containers:
  - name: web
    image: nginx:1.27.4
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: api
  namespace: ${NAMESPACE}
  labels:
    tier: api
spec:
  containers:
  - name: web
    image: nginx:1.27.4
    ports:
    - containerPort: 8080
    volumeMounts:
    - name: conf
      mountPath: /etc/nginx/conf.d
  volumes:
  - name: conf
    configMap:
      name: api-conf
---
apiVersion: v1
kind: Pod
metadata:
  name: db
  namespace: ${NAMESPACE}
  labels:
    tier: db
spec:
  containers:
  - name: web
    image: nginx:1.27.4
    ports:
    - containerPort: 5432
    volumeMounts:
    - name: conf
      mountPath: /etc/nginx/conf.d
  volumes:
  - name: conf
    configMap:
      name: db-conf
---
apiVersion: v1
kind: Service
metadata:
  name: web
  namespace: ${NAMESPACE}
spec:
  selector:
    tier: web
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: api
  namespace: ${NAMESPACE}
spec:
  selector:
    tier: api
  ports:
  - protocol: TCP
    port: 8080
    targetPort: 8080
---
apiVersion: v1
kind: Service
metadata:
  name: db
  namespace: ${NAMESPACE}
spec:
  selector:
    tier: db
  ports:
  - protocol: TCP
    port: 5432
    targetPort: 5432
---
apiVersion: v1
kind: Pod
metadata:
  name: ingress-gw
  namespace: ${CLIENT_NS}
  labels:
    role: gateway
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: rogue
  namespace: ${CLIENT_NS}
  labels:
    role: rogue
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
YAML

kubectl wait --for=condition=Ready pod/web pod/api pod/db -n "$NAMESPACE" --timeout=120s || true
kubectl wait --for=condition=Ready pod/ingress-gw pod/rogue -n "$CLIENT_NS" --timeout=120s || true

echo "Setup completed for Question 12"
