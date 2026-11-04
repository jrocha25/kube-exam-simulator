#!/bin/bash
set -e

# Question 2: node01's kubelet is told to hold back almost all of the node's
# memory for the system, so the node reports Ready with an Allocatable far below
# what it really has and anything scheduled there stays Pending on
# "Insufficient memory". The workload is pinned to node01 with a nodeSelector, so
# the scheduler cannot quietly route around the fault -- and the other questions'
# pods still have node02 and the control plane, so the blast radius stops here.
#
# The reservation is computed from the node's real capacity rather than hardcoded.
# A kind node inherits the whole host's memory, so a fixed "12Gi" is a crippling
# reservation on an 8G laptop and no reservation at all on a 32G workstation.

NAMESPACE="sched-batch"
# What Allocatable should come out at. This has to sit in a narrow band: below
# the workload's request, so the Pods stay Pending -- but comfortably above what
# the node's DaemonSets actually consume. The kubelet's default
# enforceNodeAllocatable is ["pods"], so Allocatable is not just a scheduling
# figure, it is a hard memory cap on the pods cgroup. Set it too low and
# calico-node, kube-proxy and every Pod pinned here are OOMKilled, which breaks
# other questions instead of staging this one.
LEAVE_MI=2048
REQUEST_GI=3   # the workload's per-replica memory request, above LEAVE_MI

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment batch-runner -n "$NAMESPACE" --ignore-not-found=true

if [ -f /tmp/exam/node-ssh-unavailable ]; then
    echo "WARNING: skipping question 2 setup, there is no shell on the nodes"
    exit 0
fi

NODE01=$(kubectl get nodes -l ck-x.io/alias=node01 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -z "$NODE01" ]; then
    echo "WARNING: no node carries the label ck-x.io/alias=node01; skipping question 2 setup"
    exit 0
fi

CAP=$(kubectl get node "$NODE01" -o jsonpath='{.status.capacity.memory}')
case "$CAP" in
    *Ki) CAP_MI=$(( ${CAP%Ki} / 1024 )) ;;
    *)   echo "WARNING: unexpected capacity format '$CAP'; skipping question 2 setup"; exit 0 ;;
esac

RESERVE_MI=$(( CAP_MI - LEAVE_MI ))
if [ "$RESERVE_MI" -lt 512 ]; then
    echo "WARNING: node01 reports only ${CAP_MI}Mi; too small to stage this fault"
    exit 0
fi
echo "node01 capacity ${CAP_MI}Mi, reserving ${RESERVE_MI}Mi for the system"

ssh -o ConnectTimeout=10 node01 "RESERVE_MI=${RESERVE_MI} bash -s" <<'REMOTE'
set -e
CONFIG=/var/lib/kubelet/config.yaml
cp -n "$CONFIG" "${CONFIG}.ck-x-original" 2>/dev/null || true

# Drop any reservation a previous attempt planted, then add the sized one.
sed -i '/^systemReserved:/,/^[^ ]/{ /^systemReserved:/d; /^  /d }' "$CONFIG"

cat >> "$CONFIG" <<YAML
systemReserved:
  memory: "${RESERVE_MI}Mi"
  cpu: "100m"
YAML

systemctl restart kubelet
REMOTE

# Give the kubelet time to re-register with the smaller Allocatable before the
# Deployment lands, otherwise the pods schedule and the question has no symptom.
# Bounded: a kubelet that never comes back is a WARNING, not a hang.
STAGED=no
for attempt in $(seq 1 24); do
    ALLOC=$(kubectl get node "$NODE01" -o jsonpath='{.status.allocatable.memory}' 2>/dev/null || true)
    case "$ALLOC" in
        *Ki)
            ALLOC_MI=$(( ${ALLOC%Ki} / 1024 ))
            if [ "$ALLOC_MI" -lt $(( REQUEST_GI * 1024 )) ]; then
                STAGED=yes
                echo "node01 now reports ${ALLOC_MI}Mi allocatable"
                break
            fi
            ;;
    esac
    sleep 5
done

if [ "$STAGED" != yes ]; then
    echo "WARNING: node01 still reports ${ALLOC:-unknown} allocatable memory."
    echo "WARNING: question 2 will have no symptom -- its pods will schedule normally."
fi

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: batch-runner
  namespace: $NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: batch-runner
  template:
    metadata:
      labels:
        app: batch-runner
    spec:
      nodeSelector:
        ck-x.io/alias: node01
      containers:
      - name: runner
        image: busybox:1.36
        command: ["sh", "-c", "sleep 86400"]
        resources:
          requests:
            memory: "${REQUEST_GI}Gi"
            cpu: "50m"
YAML

echo "Setup completed for Question 2"
