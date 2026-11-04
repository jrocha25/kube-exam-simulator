#!/bin/bash
set -e

# Question 9: the Role lists cronjobs and ingresses under the core API group,
# which is not where either of them lives, so both rules match nothing.
# rbac-jobs-staging exists only so the grant can be shown not to leak.
for ns in rbac-jobs rbac-jobs-staging; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl delete rolebinding scheduler-bot-jobs -n rbac-jobs --ignore-not-found=true
kubectl delete role job-manager -n rbac-jobs --ignore-not-found=true
kubectl delete serviceaccount scheduler-bot -n rbac-jobs --ignore-not-found=true

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: scheduler-bot
  namespace: rbac-jobs
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: job-manager
  namespace: rbac-jobs
rules:
- apiGroups: [""]
  resources: ["cronjobs"]
  verbs: ["get", "list", "create"]
- apiGroups: [""]
  resources: ["ingresses"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: scheduler-bot-jobs
  namespace: rbac-jobs
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: job-manager
subjects:
- kind: ServiceAccount
  name: scheduler-bot
  namespace: rbac-jobs
YAML

echo "Setup completed for Question 9"
