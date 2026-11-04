#!/bin/bash
set -e

# Question 12: a legacy Ingress that has to be reproduced as an HTTPRoute
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

kubectl create namespace edge-migrate --dry-run=client -o yaml | kubectl apply -f -

# The pre-clean of the Gateway API objects only works while their CRDs exist --
# without them kubectl errors out and "set -e" would abort the whole setup.
if [ "$GATEWAY_API_OK" = yes ]; then
    kubectl delete httproute web-route -n edge-migrate --ignore-not-found=true
    kubectl delete gateway web-gw -n edge-migrate --ignore-not-found=true
fi
kubectl delete ingress legacy-web -n edge-migrate --ignore-not-found=true

kubectl apply -f - <<EOF || echo "WARNING: not every resource could be created (is the Gateway API available?)"
apiVersion: apps/v1
kind: Deployment
metadata:
  name: catalog
  namespace: edge-migrate
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
  name: catalog-svc
  namespace: edge-migrate
spec:
  type: ClusterIP
  selector:
    app: catalog
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: profile
  namespace: edge-migrate
spec:
  replicas: 2
  selector:
    matchLabels:
      app: profile
  template:
    metadata:
      labels:
        app: profile
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
  name: profile-svc
  namespace: edge-migrate
spec:
  type: ClusterIP
  selector:
    app: profile
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: legacy-web
  namespace: edge-migrate
spec:
  ingressClassName: traefik
  rules:
  - host: www.helioscale.io
    http:
      paths:
      - path: /catalog
        pathType: Prefix
        backend:
          service:
            name: catalog-svc
            port:
              number: 80
      - path: /profile
        pathType: Prefix
        backend:
          service:
            name: profile-svc
            port:
              number: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: web-gw
  namespace: edge-migrate
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

kubectl rollout status deployment/catalog -n edge-migrate --timeout=180s || true
kubectl rollout status deployment/profile -n edge-migrate --timeout=180s || true

echo "Setup completed for Question 12"
