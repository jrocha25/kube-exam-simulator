#!/bin/bash
set -e

# Question 5: node02's kubelet is given a configuration it cannot start with, so
# the node goes NotReady and the Deployment pinned to it loses its Pods. The
# fault is a client CA path in /var/lib/kubelet/config.yaml that does not exist;
# the kubelet logs exactly that and exits, systemd restarts it, and the loop
# is what "journalctl -u kubelet" shows the candidate.
#
# The workload is pinned to node02 with a nodeSelector so the scheduler cannot
# route around the fault, and node02 belongs to this question alone -- nothing
# else in the lab schedules there and no validation counts nodes globally.
# The Deployment lands first, while the node is still healthy, so its Pods
# were once Running: after ~5 minutes of NotReady the node controller evicts
# them and the replacements sit Pending, which is the symptom in the question.

NAMESPACE="node-outage"
DEPLOYMENT="sensor-relay"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# q0_setup.sh cordoned node02 so that no other question's fixture lands on the
# node this one is about to break. This is the question that owns it: uncordon
# now, so the Deployment below can land, and leave it uncordoned -- the fault is
# the kubelet, and the candidate must not have a cordon to find on top of it.
NODE02=$(kubectl get nodes -l ck-x.io/alias=node02 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
[ -n "$NODE02" ] && kubectl uncordon "$NODE02" >/dev/null 2>&1 || true

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
        ck-x.io/alias: node02
      containers:
      - name: relay
        image: nginx:1.27.4
        ports:
        - containerPort: 80
YAML

if [ -f /tmp/exam/node-ssh-unavailable ]; then
    echo "WARNING: skipping the question 5 fault, there is no shell on the nodes"
    exit 0
fi

if [ -z "$NODE02" ]; then
    echo "WARNING: no node carries the label ck-x.io/alias=node02; skipping the question 5 fault"
    exit 0
fi

# Let the Pods land on a healthy node first; bounded, so a slow image pull is a
# warning rather than a stalled warm-up.
kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=120s \
    || echo "WARNING: $DEPLOYMENT did not become ready before the fault was planted"

ssh -o ConnectTimeout=10 node02 'bash -s' <<'REMOTE'
set -e
CONFIG=/var/lib/kubelet/config.yaml
cp -n "$CONFIG" "${CONFIG}.ck-x-original" 2>/dev/null || true
# The kubelet refuses to start when the client CA file is missing.
sed -i 's#clientCAFile: /etc/kubernetes/pki/ca.crt#clientCAFile: /etc/kubernetes/pki/ca.pem#' "$CONFIG"
grep -q 'ca.pem' "$CONFIG" || echo "WARNING: the clientCAFile line was not found in $CONFIG"
systemctl restart kubelet || true
REMOTE

# Confirm the symptom is real before moving on. The node controller needs
# ~40s of missed heartbeats to flip the condition.
STAGED=no
for _ in $(seq 1 18); do
    READY=$(kubectl get node "$NODE02" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [ "$READY" != "True" ]; then
        STAGED=yes
        break
    fi
    sleep 5
done
[ "$STAGED" = yes ] || echo "WARNING: node02 still reports Ready; the kubelet fault did not take"

echo "Setup completed for Question 5 (node02 is NotReady, by design)"
