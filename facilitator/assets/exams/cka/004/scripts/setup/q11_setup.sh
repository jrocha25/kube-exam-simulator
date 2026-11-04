#!/bin/bash
set -e

# Question 11: first Gateway and HTTPRoute
#
# The cluster ships the standard-channel Gateway API CRDs with the bundled Traefik
# chart, and env-setup turns on Traefik's Gateway provider, so there is nothing to
# install here. The chart is applied asynchronously after the cluster comes up
# though, so wait for the CRDs to appear before waiting on their condition --
# "kubectl wait" errors out immediately on a resource that does not exist yet.
#
# This is the only script that waits at length: setup scripts run in glob order, so
# q11 runs before q12-q17, and it leaves a marker they read instead of each paying
# the timeout again. Every wait here is bounded -- a cluster without the Gateway API
# has to say so in minutes rather than stall the whole warm-up.
GATEWAY_MARKER=/tmp/exam/gateway-api-unavailable

mkdir -p /tmp/exam
rm -f "$GATEWAY_MARKER"

# Poll for each CRD for at most 120s, reporting progress so the log shows the wait
# is alive rather than hung.
GATEWAY_API_OK=yes
for crd in gatewayclasses gateways httproutes; do
    FOUND=no
    for attempt in $(seq 1 24); do
        if kubectl get "crd/${crd}.gateway.networking.k8s.io" >/dev/null 2>&1; then
            FOUND=yes
            break
        fi
        if [ $(( attempt % 6 )) -eq 0 ]; then
            echo "Waiting for CRD ${crd}.gateway.networking.k8s.io ($(( attempt * 5 ))s)..."
        fi
        sleep 5
    done

    if [ "$FOUND" != yes ]; then
        GATEWAY_API_OK=no
        continue
    fi

    kubectl wait --for=condition=established --timeout=60s "crd/${crd}.gateway.networking.k8s.io" \
        || GATEWAY_API_OK=no
done

# Wait for the traefik GatewayClass to be accepted, otherwise a Gateway created by
# the candidate would never be programmed.
if [ "$GATEWAY_API_OK" = yes ]; then
    STATUS=""
    for attempt in $(seq 1 24); do
        STATUS=$(kubectl get gatewayclass traefik -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)
        if [ "$STATUS" = "True" ]; then
            break
        fi
        if [ $(( attempt % 6 )) -eq 0 ]; then
            echo "Waiting for GatewayClass traefik to be accepted ($(( attempt * 5 ))s)..."
        fi
        sleep 5
    done

    if [ "$STATUS" != "True" ]; then
        GATEWAY_API_OK=no
        echo "WARNING: GatewayClass traefik did not become Accepted in time"
    fi
fi

# Leave the marker so q12-q17 skip their own wait, and say what to actually do
# about it rather than only naming the CRD that is missing.
if [ "$GATEWAY_API_OK" != yes ]; then
    echo "unavailable" > "$GATEWAY_MARKER"
    echo "WARNING: the Gateway API is not available in this cluster."
    echo "WARNING: the cluster image in use does not enable Traefik's kubernetesGateway"
    echo "WARNING: provider, so the Gateway API CRDs were never installed."
    echo "WARNING: rebuild the cluster image with:  ./start.sh --rebuild"
    echo "WARNING: questions 11-17 will not work until then."
fi

kubectl create namespace edge-basic --dry-run=client -o yaml | kubectl apply -f -

mkdir -p /tmp/exam/q11
rm -f /tmp/exam/q11/gatewayclass.txt

# The pre-clean of the Gateway API objects only works while their CRDs exist --
# without them kubectl errors out and "set -e" would abort the whole setup.
if [ "$GATEWAY_API_OK" = yes ]; then
    kubectl delete httproute search-route -n edge-basic --ignore-not-found=true
    kubectl delete gateway edge-gw -n edge-basic --ignore-not-found=true
fi
kubectl delete deployment search-api -n edge-basic --ignore-not-found=true
kubectl delete service search-svc -n edge-basic --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: search-api
  namespace: edge-basic
spec:
  replicas: 2
  selector:
    matchLabels:
      app: search-api
  template:
    metadata:
      labels:
        app: search-api
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
  name: search-svc
  namespace: edge-basic
spec:
  type: ClusterIP
  selector:
    app: search-api
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
EOF

kubectl rollout status deployment/search-api -n edge-basic --timeout=180s || true

echo "Setup completed for Question 11"
