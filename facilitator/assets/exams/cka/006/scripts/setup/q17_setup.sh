#!/bin/bash
set -e

# Question 17: taints, tolerations and node affinity. node02 is reserved for a
# workload that has to both tolerate the taint and be steered onto the node --
# a toleration alone only grants permission to land there, it does not attract
# anything, which is the distinction the question is testing.

NAMESPACE="sched-pin"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment --all -n "$NAMESPACE" --ignore-not-found=true

NODE02=$(kubectl get nodes -l ck-x.io/alias=node02 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [ -n "$NODE02" ]; then
    # Clear a taint or label left by a previous attempt so the question starts clean.
    kubectl taint node "$NODE02" workload- >/dev/null 2>&1 || true
    kubectl label node "$NODE02" tier- >/dev/null 2>&1 || true
else
    echo "WARNING: no node carries the label ck-x.io/alias=node02"
fi

echo "Setup completed for Question 17"
