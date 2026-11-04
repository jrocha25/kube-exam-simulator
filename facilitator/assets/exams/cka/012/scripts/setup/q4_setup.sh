#!/bin/bash
set -e

# Question 4: a policy whose two selectors were split into two "from" entries.
#
# The seeded policy reads
#     from:
#       - namespaceSelector: net-array-edge
#       - podSelector: station-role=collector
# which is an OR, so it admits every Pod in net-array-edge *and* every
# collector-labelled Pod in any namespace. The approved path works on the seeded
# state, which is why that check is only worth one mark; the two marks that
# matter are the two paths that must stop working.
#
# The policy is deleted and re-applied on every warm-up so that a candidate who
# fixed it last time starts from the broken state again.

NAMESPACE="net-array"
EDGE_NS="net-array-edge"

for ns in "$NAMESPACE" "$EDGE_NS"; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: ConfigMap
metadata:
  name: relay-port
  namespace: net-array
data:
  ports.conf: |
    server {
        listen 8443;
        location / { return 200 "station relay\n"; }
    }
---
apiVersion: v1
kind: Pod
metadata:
  name: station-relay
  namespace: net-array
  labels:
    app: station-relay
spec:
  containers:
  - name: relay
    image: nginx:1.27.4
    volumeMounts:
    - name: conf
      mountPath: /etc/nginx/conf.d/ports.conf
      subPath: ports.conf
  volumes:
  - name: conf
    configMap:
      name: relay-port
---
apiVersion: v1
kind: Pod
metadata:
  name: local-collector
  namespace: net-array
  labels:
    station-role: collector
spec:
  containers:
  - name: client
    image: nginx:1.27.4
---
apiVersion: v1
kind: Pod
metadata:
  name: edge-collector
  namespace: net-array-edge
  labels:
    station-role: collector
spec:
  containers:
  - name: client
    image: nginx:1.27.4
---
apiVersion: v1
kind: Pod
metadata:
  name: edge-visitor
  namespace: net-array-edge
spec:
  containers:
  - name: client
    image: nginx:1.27.4
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: array-ingress
  namespace: net-array
spec:
  podSelector:
    matchLabels:
      app: station-relay
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: net-array-edge
    - podSelector:
        matchLabels:
          station-role: collector
    ports:
    - protocol: TCP
      port: 8443
YAML

kubectl wait --for=condition=Ready pod/station-relay pod/local-collector -n "$NAMESPACE" --timeout=120s \
    || echo "WARNING: not every Pod in ${NAMESPACE} became ready"
kubectl wait --for=condition=Ready pod/edge-collector pod/edge-visitor -n "$EDGE_NS" --timeout=120s \
    || echo "WARNING: not every Pod in ${EDGE_NS} became ready"

echo "Setup completed for Question 4"
