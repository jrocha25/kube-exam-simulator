#!/bin/bash
set -e

# Question 8: an egress policy that locks the frontend down to the backend and,
# in doing so, also cuts off its DNS lookups to kube-dns.
kubectl create namespace net-egress --dry-run=client -o yaml | kubectl apply -f -

kubectl delete networkpolicy --all -n net-egress --ignore-not-found=true
kubectl delete pod frontend backend other -n net-egress --ignore-not-found=true --timeout=60s || true
kubectl delete service backend -n net-egress --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: frontend
  namespace: net-egress
  labels:
    app: frontend
spec:
  containers:
  - name: probe
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
---
apiVersion: v1
kind: Pod
metadata:
  name: backend
  namespace: net-egress
  labels:
    app: backend
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
  name: other
  namespace: net-egress
  labels:
    app: other
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
  name: backend
  namespace: net-egress
spec:
  type: ClusterIP
  selector:
    app: backend
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
YAML

kubectl wait --for=condition=Ready pod/frontend pod/backend pod/other -n net-egress --timeout=120s || true

kubectl apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-egress
  namespace: net-egress
spec:
  podSelector:
    matchLabels:
      app: frontend
  policyTypes:
  - Egress
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: backend
    ports:
    - protocol: TCP
      port: 80
YAML

echo "Setup completed for Question 8"
