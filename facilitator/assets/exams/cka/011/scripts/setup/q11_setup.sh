#!/bin/bash
set -e

# Question 11: reaching the API server from inside a Pod with its own identity.
#
# The ConfigMap carries a value generated fresh on every warm-up. The validation
# reads that value from the live cluster and looks for it in the captured file,
# so the answer cannot be typed out or carried over from a previous attempt --
# it has to have come back from the API server.
#
# The image is curlimages/curl, not busybox: busybox's ssl_client cannot
# complete the handshake with the API server and fails before authorization is
# ever reached, which makes a correct answer look broken to the candidate.

NAMESPACE="api-beacon"
DIR="/tmp/exam/q11"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete pod beacon-probe -n "$NAMESPACE" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true

mkdir -p "$DIR"
rm -f "${DIR}/configmaps.json"

TOKEN_VALUE="rwy-$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')"

kubectl apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: beacon-reader
  namespace: $NAMESPACE
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: beacon-reader
  namespace: $NAMESPACE
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: beacon-reader
  namespace: $NAMESPACE
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: beacon-reader
subjects:
- kind: ServiceAccount
  name: beacon-reader
  namespace: $NAMESPACE
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: runway-status
  namespace: $NAMESPACE
data:
  clearance: "$TOKEN_VALUE"
YAML

echo "Setup completed for Question 11"
