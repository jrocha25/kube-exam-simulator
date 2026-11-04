#!/bin/bash
set -e

# Question 16: two backends behind one Gateway the candidate builds from scratch.
# q0 does the authoritative Gateway API probe; if it found nothing there is no
# point paying a timeout again here.
if [ -f /tmp/exam/gateway-api-unavailable ]; then
    echo "WARNING: the Gateway API is not available -- skipping the Gateway resources"
    echo "WARNING: for this question. See the warning from the shared setup."
    GATEWAY_API_OK=no
else
    GATEWAY_API_OK=yes
fi

kubectl create namespace edge-shop --dry-run=client -o yaml | kubectl apply -f -

if [ "$GATEWAY_API_OK" = yes ]; then
    kubectl delete httproute shop-route -n edge-shop --ignore-not-found=true
    kubectl delete gateway shop-gw -n edge-shop --ignore-not-found=true
fi
kubectl delete deployment shop-web shop-api -n edge-shop --ignore-not-found=true
kubectl delete service shop-web shop-api -n edge-shop --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-web
  namespace: edge-shop
spec:
  replicas: 2
  selector:
    matchLabels:
      app: shop-web
  template:
    metadata:
      labels:
        app: shop-web
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
  name: shop-web
  namespace: edge-shop
spec:
  type: ClusterIP
  selector:
    app: shop-web
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop-api
  namespace: edge-shop
spec:
  replicas: 2
  selector:
    matchLabels:
      app: shop-api
  template:
    metadata:
      labels:
        app: shop-api
    spec:
      containers:
      - name: api
        image: nginx:1.27.4
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: shop-api
  namespace: edge-shop
spec:
  type: ClusterIP
  selector:
    app: shop-api
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
YAML

kubectl rollout status deployment/shop-web -n edge-shop --timeout=180s || true
kubectl rollout status deployment/shop-api -n edge-shop --timeout=180s || true

echo "Setup completed for Question 16"
