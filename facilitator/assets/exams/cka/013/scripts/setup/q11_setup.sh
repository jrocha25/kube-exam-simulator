#!/bin/bash
set -e

# Question 11: a Service with no selector whose EndpointSlice is written by hand.
# The backends live in another namespace on purpose: a selector could not reach
# them, which is the honest reason to manage endpoints yourself. Each backend
# answers with its own name, so the validation can tell which one served it.

BACKEND_NS="net-vault-backend"
CLIENT_NS="net-vault"

kubectl create namespace "$BACKEND_NS" --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace "$CLIENT_NS" --dry-run=client -o yaml | kubectl apply -f -

for name in vault-a vault-b; do
    kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $name
  namespace: $BACKEND_NS
  labels:
    app: vault
    member: $name
spec:
  nodeSelector:
    ck-x.io/alias: node01
  containers:
  - name: server
    image: busybox:1.36
    command:
    - sh
    - -c
    - mkdir -p /www && echo $name > /www/index.html && echo "vault_up{member=\"$name\"} 1" > /www/metrics && httpd -p 8080 -h /www && httpd -p 9100 -h /www && exec sleep 2147483647
    ports:
    - name: api
      containerPort: 8080
    - name: metrics
      containerPort: 9100
YAML
done

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: vault-client
  namespace: $CLIENT_NS
spec:
  nodeSelector:
    ck-x.io/alias: node01
  containers:
  - name: client
    image: busybox:1.36
    command: ["sleep", "2147483647"]
YAML

kubectl wait --for=condition=Ready pod/vault-a pod/vault-b -n "$BACKEND_NS" --timeout=90s >/dev/null \
    || echo "WARNING: the vault backends did not become ready"
kubectl wait --for=condition=Ready pod/vault-client -n "$CLIENT_NS" --timeout=90s >/dev/null \
    || echo "WARNING: vault-client did not become ready"

echo "Setup completed for Question 11"
