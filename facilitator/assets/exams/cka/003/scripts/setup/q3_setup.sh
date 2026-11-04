#!/bin/bash
set -e

# Question 3: DaemonSet that must run on every node
kubectl create namespace node-agents --dry-run=client -o yaml | kubectl apply -f -

kubectl delete daemonset log-agent -n node-agents --ignore-not-found=true

echo "Setup completed for Question 3"
