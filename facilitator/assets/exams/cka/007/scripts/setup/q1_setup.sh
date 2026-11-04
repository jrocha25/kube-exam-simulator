#!/bin/bash
set -e

# Question 1: three ConfigMaps, so a resourceNames grant can be shown to reach
# two of them and not the third.
kubectl create namespace rbac-report --dry-run=client -o yaml | kubectl apply -f -

kubectl delete rolebinding report-reader-binding -n rbac-report --ignore-not-found=true
kubectl delete role config-reader -n rbac-report --ignore-not-found=true
kubectl delete serviceaccount report-reader -n rbac-report --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-settings
  namespace: rbac-report
data:
  log_level: "info"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: feature-flags
  namespace: rbac-report
data:
  new_checkout: "true"
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: billing-secrets
  namespace: rbac-report
data:
  account_id: "0000-1111"
YAML

echo "Setup completed for Question 1"
