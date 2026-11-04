#!/bin/bash
set -e

# Question 1: two faults in the auxiliary cluster's control plane, staged in an
# order that leaves evidence of both.
#
#   1. The controller manager's kubeconfig hostPath points at a file that does
#      not exist. The volume is "type: FileOrCreate", so the kubelet creates an
#      empty file and the container mounts it cleanly -- the controller manager
#      then crashloops on "no configuration has been provided".
#   2. With the controller manager down, the Deployment relay-hub is created. It
#      gets no ReplicaSet, which is the symptom the candidate is told about.
#   3. The API server's --etcd-servers is moved to a port nothing listens on, so
#      the API server exits and kubectl on the node answers "connection refused".
#
# Fixing only the API server leaves relay-hub without Pods, so the question
# cannot be finished without finding the second fault. Nothing is backed up on
# the node: a ".orig" manifest next to the broken one would be the answer.

export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

NAMESPACE="cp-relay"
DEPLOYMENT="relay-hub"
STATE_DIR=/tmp/exam/q1

mkdir -p "$STATE_DIR"

if [ -f /tmp/exam/aux-cluster-unavailable ]; then
    echo "WARNING: the auxiliary cluster is unavailable, skipping setup for question 1"
    exit 0
fi

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment "$DEPLOYMENT" -n "$NAMESPACE" --ignore-not-found=true

KCM_POD=$(kubectl get pods -n kube-system -l component=kube-controller-manager \
    -o jsonpath='{.items[0].metadata.name}')
OLD_HASH=$(kubectl get pod "$KCM_POD" -n kube-system \
    -o jsonpath='{.metadata.annotations.kubernetes\.io/config\.hash}')

# Fault 1: the controller manager. Only the hostPath line changes; the
# mountPath and the --kubeconfig flag still name the right file inside the
# container, so the manifest reads as plausible at a glance.
ssh -o ConnectTimeout=10 aux 'bash -s' <<'REMOTE'
set -e
MANIFEST=/etc/kubernetes/manifests/kube-controller-manager.yaml
sed -i 's#^\(\s*\)path: /etc/kubernetes/controller-manager.conf$#\1path: /etc/kubernetes/controller-manager.config#' "$MANIFEST"
grep -q 'path: /etc/kubernetes/controller-manager.config$' "$MANIFEST" \
    || echo "WARNING: the controller manager's kubeconfig hostPath was not found in $MANIFEST"
REMOTE

# Wait, bounded, until the kubelet has replaced the controller manager with the
# broken one: a new config hash on the mirror Pod and a container that is not
# ready. Creating the Deployment any earlier would let the old controller
# manager give it a ReplicaSet.
KCM_DOWN=no
for _ in $(seq 1 24); do
    HASH=$(kubectl get pods -n kube-system -l component=kube-controller-manager \
        -o jsonpath='{.items[0].metadata.annotations.kubernetes\.io/config\.hash}' 2>/dev/null || true)
    READY=$(kubectl get pods -n kube-system -l component=kube-controller-manager \
        -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || true)
    if [ -n "$HASH" ] && [ "$HASH" != "$OLD_HASH" ] && [ "$READY" != "true" ]; then
        KCM_DOWN=yes
        break
    fi
    sleep 5
done
[ "$KCM_DOWN" = yes ] || echo "WARNING: the controller manager did not go down within 120s"
sleep 5

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT
  namespace: $NAMESPACE
  labels:
    app: $DEPLOYMENT
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $DEPLOYMENT
  template:
    metadata:
      labels:
        app: $DEPLOYMENT
    spec:
      containers:
      - name: relay
        image: nginx:1.27.4
        ports:
        - containerPort: 80
YAML

kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.metadata.uid}' > "$STATE_DIR/relay-hub.uid"

sleep 5
if [ -n "$(kubectl get replicasets -n "$NAMESPACE" -o name 2>/dev/null)" ]; then
    echo "WARNING: relay-hub already has a ReplicaSet; the controller manager was still running"
fi

# Fault 2: the API server. It retries etcd for a while before it gives up, so
# wait (bounded) until the API really refuses.
ssh -o ConnectTimeout=10 aux 'bash -s' <<'REMOTE'
set -e
MANIFEST=/etc/kubernetes/manifests/kube-apiserver.yaml
sed -i 's#--etcd-servers=https://127.0.0.1:2379#--etcd-servers=https://127.0.0.1:2397#' "$MANIFEST"
grep -q -- '--etcd-servers=https://127.0.0.1:2397' "$MANIFEST" \
    || echo "WARNING: the --etcd-servers flag was not found in $MANIFEST"
REMOTE

API_DOWN=no
for _ in $(seq 1 18); do
    if ! kubectl --request-timeout=5s get --raw /readyz >/dev/null 2>&1; then
        API_DOWN=yes
        break
    fi
    sleep 5
done
[ "$API_DOWN" = yes ] || echo "WARNING: the auxiliary API server still answers; the fault did not take"

echo "Setup completed for Question 1 (the auxiliary control plane is down, by design)"
