#!/bin/bash
set -e

# Question 9: a DaemonSet that also has to land on the control plane. Only the
# namespace is staged. The control-plane taint it has to tolerate is the one
# kubeadm sets (node-role.kubernetes.io/control-plane:NoSchedule); the aux
# cluster's is cleared by env-setup-kind, this one's is not.

NAMESPACE="ds-fleet"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete daemonset node-collector -n "$NAMESPACE" --ignore-not-found=true

echo "Setup completed for Question 9"
