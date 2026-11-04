#!/bin/bash
set -e

# Question 1: the candidate adds a context to a kubeconfig file.
#
# The file has to be a *working* one -- the final check runs kubectl against it
# and expects the new context's default namespace to take effect -- so the
# cluster, CA and client credentials are copied out of the candidate's own
# kubeconfig rather than invented. Only the contexts section is staged wrong.

NAMESPACE="ops-access"
DIR="/tmp/exam/q1"
KCFG="${DIR}/ops.kubeconfig"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: windsock
  namespace: $NAMESPACE
  labels:
    app: windsock
spec:
  containers:
  - name: windsock
    image: nginx:1.27.4
YAML

mkdir -p "$DIR"
rm -f "$KCFG"

SERVER=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.server}')
CA=$(kubectl config view --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
CERT=$(kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}')
KEY=$(kubectl config view --raw -o jsonpath='{.users[0].user.client-key-data}')

if [ -z "$SERVER" ] || [ -z "$CERT" ]; then
    echo "WARNING: could not read the candidate kubeconfig; question 1 will not work"
else
    cat > "$KCFG" <<YAML
apiVersion: v1
kind: Config
clusters:
- name: airops
  cluster:
    server: ${SERVER}
    certificate-authority-data: ${CA}
users:
- name: tower-ops
  user:
    client-certificate-data: ${CERT}
    client-key-data: ${KEY}
contexts:
- name: bootstrap
  context:
    cluster: airops
    user: tower-ops
current-context: bootstrap
preferences: {}
YAML
    chmod 600 "$KCFG"
fi

echo "Setup completed for Question 1"
