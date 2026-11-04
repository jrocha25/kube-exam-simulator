#!/bin/bash
set -e

# Question 3: one policy that has to carry an AND rule and an OR rule at once.
#
# The server listens on two ports, and four clients are staged so that traffic
# alone decides the question:
#
#   net-tremor-api/gateway-allowed   right namespace, right Pod label -> 8443 yes
#   net-tremor-api/probe-plain       right namespace, no Pod label    -> 8443 no
#   net-tremor/gateway-outsider      wrong namespace, right label     -> 8443 no
#   net-tremor-wave/wave-any         whole namespace allowed on 9100  -> 9100 yes, 8443 no
#
# A policy that puts the namespaceSelector and the podSelector in two separate
# "from" entries reads as OR and lets probe-plain and gateway-outsider through,
# so no jq inspection of the rule shape is needed to catch it.
#
# nginx is Debian based and therefore ships the bash whose /dev/tcp the probes
# use; the image has no curl and no wget. The two-port server is the ConfigMap
# shape cka/011 q4 uses.

NAMESPACE="net-tremor"
API_NS="net-tremor-api"
WAVE_NS="net-tremor-wave"

for ns in "$NAMESPACE" "$API_NS" "$WAVE_NS"; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl label namespace "$API_NS" seismo.io/tier=api --overwrite
kubectl label namespace "$WAVE_NS" seismo.io/tier- >/dev/null 2>&1 || true
kubectl label namespace "$NAMESPACE" seismo.io/tier- >/dev/null 2>&1 || true

# A previous attempt's answer must not survive into this one.
kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: tremor-ports
  namespace: net-tremor
data:
  ports.conf: |
    server {
        listen 8443;
        location / { return 200 "tremor ingest\n"; }
    }
    server {
        listen 9100;
        location / { return 200 "tremor metrics\n"; }
    }
---
apiVersion: v1
kind: Pod
metadata:
  name: tremor-ingest
  namespace: net-tremor
  labels:
    app: tremor-ingest
spec:
  containers:
  - name: ingest
    image: nginx:1.27.4
    volumeMounts:
    - name: conf
      mountPath: /etc/nginx/conf.d/ports.conf
      subPath: ports.conf
  volumes:
  - name: conf
    configMap:
      name: tremor-ports
---
apiVersion: v1
kind: Pod
metadata:
  name: gateway-outsider
  namespace: net-tremor
  labels:
    station-role: gateway
spec:
  containers:
  - name: client
    image: nginx:1.27.4
---
apiVersion: v1
kind: Pod
metadata:
  name: gateway-allowed
  namespace: net-tremor-api
  labels:
    station-role: gateway
spec:
  containers:
  - name: client
    image: nginx:1.27.4
---
apiVersion: v1
kind: Pod
metadata:
  name: probe-plain
  namespace: net-tremor-api
spec:
  containers:
  - name: client
    image: nginx:1.27.4
---
apiVersion: v1
kind: Pod
metadata:
  name: wave-any
  namespace: net-tremor-wave
  labels:
    app: wave-any
spec:
  containers:
  - name: client
    image: nginx:1.27.4
YAML

kubectl wait --for=condition=Ready pod/tremor-ingest pod/gateway-outsider -n "$NAMESPACE" --timeout=120s \
    || echo "WARNING: not every Pod in ${NAMESPACE} became ready"
kubectl wait --for=condition=Ready pod/gateway-allowed pod/probe-plain -n "$API_NS" --timeout=120s \
    || echo "WARNING: not every Pod in ${API_NS} became ready"
kubectl wait --for=condition=Ready pod/wave-any -n "$WAVE_NS" --timeout=120s \
    || echo "WARNING: the client Pod in ${WAVE_NS} did not become ready"

echo "Setup completed for Question 3"
