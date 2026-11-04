#!/bin/bash
set -e

# Question 18: a healthy backend, a Gateway that publishes one hostname on a
# listener named "public", and a route that names a listener that does not exist
# and a hostname the Gateway never serves.
if [ -f /tmp/exam/gateway-api-unavailable ]; then
    echo "WARNING: the Gateway API is not available -- skipping the Gateway resources"
    echo "WARNING: for this question. See the warning from the shared setup."
    GATEWAY_API_OK=no
else
    GATEWAY_API_OK=yes
fi

kubectl create namespace edge-stuck --dry-run=client -o yaml | kubectl apply -f -

if [ "$GATEWAY_API_OK" = yes ]; then
    kubectl delete httproute catalog-route -n edge-stuck --ignore-not-found=true
    kubectl delete gateway edge-gw -n edge-stuck --ignore-not-found=true
fi
kubectl delete deployment catalog -n edge-stuck --ignore-not-found=true
kubectl delete service catalog -n edge-stuck --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
  namespace: edge-stuck
spec:
  replicas: 2
  selector:
    matchLabels:
      app: catalog
  template:
    metadata:
      labels:
        app: catalog
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
  name: catalog
  namespace: edge-stuck
spec:
  type: ClusterIP
  selector:
    app: catalog
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
YAML

if [ "$GATEWAY_API_OK" = yes ]; then
    kubectl apply -f - <<YAML || echo "WARNING: the Gateway resources for question 18 could not be created"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: edge-gw
  namespace: edge-stuck
spec:
  gatewayClassName: traefik
  listeners:
  - name: public
    port: 80
    protocol: HTTP
    hostname: catalog.helioscale.io
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: catalog-route
  namespace: edge-stuck
spec:
  parentRefs:
  - name: edge-gw
    sectionName: http
  hostnames:
  - shop.helioscale.io
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: catalog
      port: 80
YAML
fi

kubectl rollout status deployment/catalog -n edge-stuck --timeout=180s || true

echo "Setup completed for Question 18"
