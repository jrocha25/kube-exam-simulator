#!/bin/bash
set -e

# Question 17: Gateway API stack seeded with a class name that does not resolve,
# a listener/route hostname mismatch and a backend port that is not served
# q11 runs first in glob order and does the authoritative Gateway API probe; if it
# found nothing there is no point paying the timeout again here.
if [ -f /tmp/exam/gateway-api-unavailable ]; then
    echo "WARNING: the Gateway API is not available -- skipping the Gateway resources"
    echo "WARNING: for this question. See the warning from question 11's setup."
    GATEWAY_API_OK=no
else
    GATEWAY_API_OK=yes
    for crd in gateways httproutes; do
        for _ in $(seq 1 12); do
            if kubectl get "crd/${crd}.gateway.networking.k8s.io" >/dev/null 2>&1; then
                break
            fi
            sleep 5
        done
        kubectl wait --for=condition=established --timeout=30s "crd/${crd}.gateway.networking.k8s.io" \
            || { GATEWAY_API_OK=no; echo "WARNING: CRD ${crd}.gateway.networking.k8s.io is not established"; }
    done
fi

kubectl create namespace edge-broken --dry-run=client -o yaml | kubectl apply -f -

# The pre-clean of the Gateway API objects only works while their CRDs exist --
# without them kubectl errors out and "set -e" would abort the whole setup.
if [ "$GATEWAY_API_OK" = yes ]; then
    kubectl delete httproute shop-route -n edge-broken --ignore-not-found=true
    kubectl delete gateway shop-gw -n edge-broken --ignore-not-found=true
fi
kubectl delete deployment shop -n edge-broken --ignore-not-found=true
kubectl delete service shop-svc -n edge-broken --ignore-not-found=true

kubectl apply -f - <<EOF || echo "WARNING: not every resource could be created (is the Gateway API available?)"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shop
  namespace: edge-broken
spec:
  replicas: 3
  selector:
    matchLabels:
      app: shop
  template:
    metadata:
      labels:
        app: shop
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
  name: shop-svc
  namespace: edge-broken
spec:
  type: ClusterIP
  selector:
    app: shop
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shop-gw
  namespace: edge-broken
spec:
  gatewayClassName: helioscale-edge
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    hostname: shop.helioscale.io
    allowedRoutes:
      namespaces:
        from: Same
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: shop-route
  namespace: edge-broken
spec:
  parentRefs:
  - name: shop-gw
  hostnames:
  - store.helioscale.io
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: shop-svc
      port: 8080
EOF

kubectl rollout status deployment/shop -n edge-broken --timeout=180s || true

echo "Setup completed for Question 17"
