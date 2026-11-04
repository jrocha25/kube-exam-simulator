#!/bin/bash
set -e

# Question 6: four candidate NetworkPolicies on disk; exactly one of them is the
# least permissive policy that still lets crane-ui reach harbor-api on 8080.
#
#   api-ingress-1  any Pod in harbor-ui, port 8080          -- too broad
#   api-ingress-2  crane-ui Pods in harbor-ui, port 8080    -- the answer
#   api-ingress-3  crane-ui Pods in any namespace, any port -- too broad
#   api-ingress-4  crane-ui Pods in harbor-ui, port 80      -- does not work
#
# harbor-tools runs a Pod carrying the crane-ui label on purpose, so that the
# any-namespace option is observably wider than the answer.

API_NS="harbor-api"
UI_NS="harbor-ui"
TOOLS_NS="harbor-tools"
WORKDIR=/tmp/exam/q6

mkdir -p "$WORKDIR"
rm -f "$WORKDIR"/*.yaml

for ns in "$API_NS" "$UI_NS" "$TOOLS_NS"; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done
kubectl delete networkpolicy --all -n "$API_NS" --ignore-not-found=true

server_pod() {
    cat <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: harbor-api
  namespace: $API_NS
  labels:
    app: harbor-api
spec:
  containers:
  - name: api
    image: busybox:1.36
    command:
    - sh
    - -c
    - mkdir -p /www && echo harbor-api > /www/index.html && httpd -p 8080 -h /www && httpd -p 9090 -h /www && exec sleep 2147483647
    ports:
    - containerPort: 8080
    - containerPort: 9090
YAML
}

client_pod() {
    cat <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $1
  namespace: $2
  labels:
    app: $3
spec:
  containers:
  - name: client
    image: busybox:1.36
    command: ["sleep", "2147483647"]
YAML
}

server_pod | kubectl apply -f -
client_pod crane-ui "$UI_NS" crane-ui | kubectl apply -f -
client_pod berth-ui "$UI_NS" berth-ui | kubectl apply -f -
client_pod crane-ui "$TOOLS_NS" crane-ui | kubectl apply -f -

kubectl apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: $API_NS
spec:
  podSelector: {}
  policyTypes:
  - Ingress
YAML

cat > "$WORKDIR/api-ingress-1.yaml" <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-ingress-1
  namespace: $API_NS
spec:
  podSelector:
    matchLabels:
      app: harbor-api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: $UI_NS
    ports:
    - protocol: TCP
      port: 8080
YAML

cat > "$WORKDIR/api-ingress-2.yaml" <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-ingress-2
  namespace: $API_NS
spec:
  podSelector:
    matchLabels:
      app: harbor-api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: $UI_NS
      podSelector:
        matchLabels:
          app: crane-ui
    ports:
    - protocol: TCP
      port: 8080
YAML

cat > "$WORKDIR/api-ingress-3.yaml" <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-ingress-3
  namespace: $API_NS
spec:
  podSelector:
    matchLabels:
      app: harbor-api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector: {}
      podSelector:
        matchLabels:
          app: crane-ui
YAML

cat > "$WORKDIR/api-ingress-4.yaml" <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-ingress-4
  namespace: $API_NS
spec:
  podSelector:
    matchLabels:
      app: harbor-api
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: $UI_NS
      podSelector:
        matchLabels:
          app: crane-ui
    ports:
    - protocol: TCP
      port: 80
YAML

kubectl wait --for=condition=Ready pod/harbor-api -n "$API_NS" --timeout=90s >/dev/null \
    || echo "WARNING: harbor-api is not Ready"

echo "Setup for question 6 completed"
