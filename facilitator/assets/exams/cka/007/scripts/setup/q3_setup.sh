#!/bin/bash
set -e

# Question 3: aggregation. Everything is left for the candidate; the namespace
# only holds the ServiceAccount that proves the aggregated role works.
kubectl create namespace rbac-monitor --dry-run=client -o yaml | kubectl apply -f -

kubectl delete clusterrolebinding dashboard-monitoring --ignore-not-found=true
kubectl delete clusterrole monitoring-view monitoring-pods monitoring-nodes --ignore-not-found=true
kubectl delete serviceaccount dashboard -n rbac-monitor --ignore-not-found=true

echo "Setup completed for Question 3"
