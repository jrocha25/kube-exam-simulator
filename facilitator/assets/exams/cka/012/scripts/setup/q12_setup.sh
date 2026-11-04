#!/bin/bash
set -e

# Question 12: Pending, because the node it is pinned to refuses it.
#
# The taint is NoSchedule and must stay NoSchedule. Setup glob order is
# q0, q1, q10..q13, q2..q9, so this script taints node03 after question 10's and
# question 11's fixtures are created and before questions 2..9's. NoSchedule
# never evicts a Pod that is already running, so nothing that landed on node03
# earlier is harmed -- NoExecute would delete question 10's bare Pod outright,
# with no controller to bring it back.
#
# The taint key is the lab's own. The documentation's key1=value1 would let a
# candidate paste the toleration block from the taints page without ever looking
# at the node, which is the half of this question that is actually graded.
#
# The image is pre-pulled on node03 in the background: node03's own taint keeps
# everything else off it, so this Pod's image would otherwise be pulled cold the
# moment a correct toleration lands, inside the validation window.

NAMESPACE="sched-borehole"
POD="borehole-sampler"
TAINT_KEY="seismo.io/borehole"
TAINT_VALUE="restricted"
IMAGE="busybox:1.36"
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

NODE03=$(kubectl get nodes -l ck-x.io/alias=node03 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$NODE03" ]; then
    echo "WARNING: no node carries the label ck-x.io/alias=node03, skipping setup for question 12"
    exit 0
fi

kubectl taint node "$NODE03" "${TAINT_KEY}=${TAINT_VALUE}:NoSchedule" --overwrite >/dev/null 2>&1 || \
    echo "WARNING: could not taint ${NODE03}"

kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found=true --timeout=60s >/dev/null 2>&1 || true

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: borehole-sampler
  namespace: sched-borehole
  labels:
    app: borehole-sampler
spec:
  nodeSelector:
    ck-x.io/alias: node03
  containers:
  - name: sampler
    image: busybox:1.36
    command: ["sh", "-c", "while true; do echo sampling borehole; sleep 30; done"]
YAML

if [ ! -f /tmp/exam/node-ssh-unavailable ]; then
    ssh $SSH_OPTS node03 "setsid nohup crictl pull ${IMAGE} >/dev/null 2>&1 &" >/dev/null 2>&1 || true
fi

echo "Setup completed for Question 12"
