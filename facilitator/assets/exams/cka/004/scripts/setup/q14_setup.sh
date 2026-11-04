#!/bin/bash
set -e

# Question 14: shared Gateway that must expose a second, restricted listener
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

kubectl create namespace edge-shared --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace team-orders --dry-run=client -o yaml | kubectl apply -f -
kubectl label namespace team-orders gateway-access=allowed --overwrite

# The pre-clean of the Gateway API objects only works while their CRDs exist --
# without them kubectl errors out and "set -e" would abort the whole setup.
if [ "$GATEWAY_API_OK" = yes ]; then
    kubectl delete httproute orders-route -n team-orders --ignore-not-found=true
    kubectl delete gateway shared-gw -n edge-shared --ignore-not-found=true
fi

kubectl apply -f - <<EOF || echo "WARNING: not every resource could be created (is the Gateway API available?)"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: orders
  namespace: team-orders
spec:
  replicas: 2
  selector:
    matchLabels:
      app: orders
  template:
    metadata:
      labels:
        app: orders
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
  name: orders-svc
  namespace: team-orders
spec:
  type: ClusterIP
  selector:
    app: orders
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: shared-gw
  namespace: edge-shared
spec:
  gatewayClassName: traefik
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    hostname: www.helioscale.io
    allowedRoutes:
      namespaces:
        from: Same
EOF

kubectl rollout status deployment/orders -n team-orders --timeout=180s || true

echo "Setup completed for Question 14"
