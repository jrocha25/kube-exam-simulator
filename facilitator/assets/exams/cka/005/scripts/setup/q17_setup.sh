#!/bin/bash
set -e

# Question 17: a Gateway in the platform namespace that today only accepts routes
# from its own namespace, and an application in another namespace that has to
# attach to it.
if [ -f /tmp/exam/gateway-api-unavailable ]; then
    echo "WARNING: the Gateway API is not available -- skipping the Gateway resources"
    echo "WARNING: for this question. See the warning from the shared setup."
    GATEWAY_API_OK=no
else
    GATEWAY_API_OK=yes
fi

for ns in edge-platform edge-team; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

# The candidate is asked to add this label; make sure a previous attempt is not
# still carrying it.
kubectl label namespace edge-team gateway-access- 2>/dev/null || true

if [ "$GATEWAY_API_OK" = yes ]; then
    kubectl delete httproute team-route -n edge-team --ignore-not-found=true
    kubectl delete gateway platform-gw -n edge-platform --ignore-not-found=true
fi
kubectl delete deployment team-api -n edge-team --ignore-not-found=true
kubectl delete service team-api -n edge-team --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: team-api
  namespace: edge-team
spec:
  replicas: 2
  selector:
    matchLabels:
      app: team-api
  template:
    metadata:
      labels:
        app: team-api
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
  name: team-api
  namespace: edge-team
spec:
  type: ClusterIP
  selector:
    app: team-api
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
YAML

if [ "$GATEWAY_API_OK" = yes ]; then
    kubectl apply -f - <<YAML || echo "WARNING: the Gateway for question 17 could not be created"
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: platform-gw
  namespace: edge-platform
spec:
  gatewayClassName: traefik
  listeners:
  - name: web
    port: 80
    protocol: HTTP
    hostname: "*.helioscale.io"
    allowedRoutes:
      namespaces:
        from: Same
YAML
fi

kubectl rollout status deployment/team-api -n edge-team --timeout=180s || true

echo "Setup completed for Question 17"
