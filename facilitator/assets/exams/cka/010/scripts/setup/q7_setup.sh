#!/bin/bash
set -e

# Question 7: a kubeconfig that does not work. The ServiceAccount, its Role and
# the token are all correct; the file around them carries two faults:
#
#   * the context names a user entry that does not exist ("release-bot" versus
#     the entry, which is called "releasebot") -- kubectl fails before it ever
#     opens a connection, which masks the second fault until this one is fixed
#   * the server points at port 6444, which on this jumphost is the auxiliary
#     cluster's API server: TLS connects (that cluster's certificate also names
#     k8s-api-server) and then fails with "certificate signed by unknown
#     authority", because it is a different CA. A wrong port that merely refused
#     the connection would be too easy to spot.
#
# The token is bound for 24h, longer than any exam.

NAMESPACE="kcfg-release"
SA="release-bot"
OUT=/tmp/exam/q7/release.kubeconfig
WRONG_PORT=6444

mkdir -p /tmp/exam/q7
rm -f "$OUT"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl create serviceaccount "$SA" -n "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<YAML
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: release-viewer
  namespace: $NAMESPACE
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: release-viewer
  namespace: $NAMESPACE
subjects:
- kind: ServiceAccount
  name: $SA
  namespace: $NAMESPACE
roleRef:
  kind: Role
  name: release-viewer
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: v1
kind: Pod
metadata:
  name: release-canary
  namespace: $NAMESPACE
spec:
  containers:
  - name: canary
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
YAML

TOKEN=$(kubectl create token "$SA" -n "$NAMESPACE" --duration=24h)
CA_DATA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
SERVER=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}')
WRONG_SERVER=$(echo "$SERVER" | sed -E "s#:[0-9]+\$#:${WRONG_PORT}#")

cat > "$OUT" <<YAML
apiVersion: v1
kind: Config
clusters:
- name: lab
  cluster:
    certificate-authority-data: $CA_DATA
    server: $WRONG_SERVER
users:
- name: releasebot
  user:
    token: $TOKEN
contexts:
- name: release@lab
  context:
    cluster: lab
    user: release-bot
    namespace: $NAMESPACE
current-context: release@lab
YAML
chmod 600 "$OUT"

# The original values the validation compares repairs against.
echo "$SERVER" > /tmp/exam/q7/.server

echo "Setup completed for Question 7 (release.kubeconfig is broken, by design)"
