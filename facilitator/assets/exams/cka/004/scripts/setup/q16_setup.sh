#!/bin/bash
set -e

# Question 16: a backend that lives in a different namespace from the HTTPRoute
# q11 runs first in glob order and does the authoritative Gateway API probe; if it
# found nothing there is no point paying the timeout again here.
if [ -f /tmp/exam/gateway-api-unavailable ]; then
    echo "WARNING: the Gateway API is not available -- skipping the Gateway resources"
    echo "WARNING: for this question. See the warning from question 11's setup."
    GATEWAY_API_OK=no
else
    GATEWAY_API_OK=yes
    for crd in gateways httproutes referencegrants; do
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

kubectl create namespace edge-front --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace backend-store --dry-run=client -o yaml | kubectl apply -f -

# The pre-clean of the Gateway API objects only works while their CRDs exist --
# without them kubectl errors out and "set -e" would abort the whole setup.
if [ "$GATEWAY_API_OK" = yes ]; then
    kubectl delete httproute inventory-route -n edge-front --ignore-not-found=true
    kubectl delete referencegrant allow-edge-front -n backend-store --ignore-not-found=true
    kubectl delete gateway front-gw -n edge-front --ignore-not-found=true
fi

kubectl apply -f - <<EOF || echo "WARNING: not every resource could be created (is the Gateway API available?)"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory
  namespace: backend-store
spec:
  replicas: 2
  selector:
    matchLabels:
      app: inventory
  template:
    metadata:
      labels:
        app: inventory
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
  name: inventory-svc
  namespace: backend-store
spec:
  type: ClusterIP
  selector:
    app: inventory
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: front-gw
  namespace: edge-front
spec:
  gatewayClassName: traefik
  listeners:
  - name: http
    port: 80
    protocol: HTTP
    hostname: inventory.helioscale.io
    allowedRoutes:
      namespaces:
        from: Same
EOF

kubectl rollout status deployment/inventory -n backend-store --timeout=180s || true

echo "Setup completed for Question 16"
