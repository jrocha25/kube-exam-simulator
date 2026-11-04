#!/bin/bash
set -e

# Question 8: node03 goes NotReady with two faults, layered so that fixing the
# first reveals the second.
#
#   1. /etc/default/kubelet (an EnvironmentFile of kind's kubelet unit) gains
#      --container-runtime-endpoint pointing at cri-dockerd, which this node
#      does not run. The kubelet exits at start with a CRI connection error.
#   2. /etc/kubernetes/kubelet.conf points at the API server on the wrong port.
#      Once the first fault is gone the kubelet starts, then cannot register or
#      post status -- "connection refused" in the journal, node still NotReady.
#
# Both faults are different from cka/006 q2 and cka/010 q5 (a missing client CA
# file). The question forbids a re-join, so the fix for the second has to keep
# the node's own client certificate.
#
# q0_setup.sh cordoned node03 so no other question's fixture lands on the node
# this one breaks. Uncordon it now for buoy-agent, then break it: the NotReady
# taint keeps everything else off from here on.

NAMESPACE="node-buoy"
DEPLOYMENT="buoy-agent"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

NODE03=$(grep '^node03=' /tmp/exam/nodes.env | cut -d= -f2)
[ -n "$NODE03" ] && kubectl uncordon "$NODE03" >/dev/null 2>&1 || true

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
      nodeSelector:
        ck-x.io/alias: node03
      containers:
      - name: agent
        image: nginx:1.27.4
        ports:
        - containerPort: 80
YAML

if [ -f /tmp/exam/node-ssh-unavailable ] || [ -z "$NODE03" ]; then
    echo "WARNING: skipping the question 8 faults, there is no shell on node03"
    exit 0
fi

kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=120s \
    || echo "WARNING: $DEPLOYMENT did not become ready before the faults were planted"

ssh -o ConnectTimeout=10 node03 'bash -s' <<'REMOTE'
set -e
DEFAULTS=/etc/default/kubelet
KUBECONF=/etc/kubernetes/kubelet.conf

if ! grep -q 'cri-dockerd.sock' "$DEFAULTS"; then
    sed -i 's#^KUBELET_EXTRA_ARGS=.*#& --container-runtime-endpoint=unix:///var/run/cri-dockerd.sock#' "$DEFAULTS"
fi
grep -q 'cri-dockerd.sock' "$DEFAULTS" || echo "WARNING: KUBELET_EXTRA_ARGS was not found in $DEFAULTS"

sed -i 's#^\(\s*server: https://[^:]*\):6443$#\1:6643#' "$KUBECONF"
grep -q ':6643$' "$KUBECONF" || echo "WARNING: the server line was not found in $KUBECONF"

systemctl restart kubelet || true
REMOTE

# The node controller needs ~40s of missed heartbeats to flip the condition.
STAGED=no
for _ in $(seq 1 18); do
    READY=$(kubectl get node "$NODE03" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [ "$READY" != "True" ]; then
        STAGED=yes
        break
    fi
    sleep 5
done
[ "$STAGED" = yes ] || echo "WARNING: node03 still reports Ready; the kubelet faults did not take"

echo "Setup completed for Question 8 (node03 is NotReady, by design)"
