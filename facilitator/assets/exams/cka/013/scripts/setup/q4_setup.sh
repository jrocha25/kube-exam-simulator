#!/bin/bash
set -e

# Question 4: run a Pod with the scheduler stopped. Nothing is broken here --
# the candidate stops the lab cluster's scheduler themselves. Record the
# scheduler's mirror Pod UID: moving the static Pod manifest out and back makes
# the kubelet delete and re-create the mirror Pod, which is the evidence that
# the scheduler really was stopped and started again.

NAMESPACE="sched-berth"
STATE_DIR=/tmp/exam/q4

mkdir -p "$STATE_DIR"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete pod berth-manual berth-auto -n "$NAMESPACE" --ignore-not-found=true

CP=$(grep '^controlplane=' /tmp/exam/nodes.env | cut -d= -f2)
kubectl get pod "kube-scheduler-${CP}" -n kube-system -o jsonpath='{.metadata.uid}' \
    > "$STATE_DIR/scheduler.uid" 2>/dev/null \
    || echo "WARNING: could not record the kube-scheduler mirror Pod"

echo "Setup completed for Question 4"
