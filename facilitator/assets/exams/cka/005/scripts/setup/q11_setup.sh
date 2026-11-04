#!/bin/bash
set -e

# Question 11: the Role and RoleBinding both exist and both look right at a
# glance. The binding's subject names the ServiceAccount in the wrong namespace,
# so the grant lands on an identity that nothing runs as.
for ns in rbac-broken rbac-broken-staging; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
done

kubectl delete rolebinding sync-agent-binding -n rbac-broken --ignore-not-found=true
kubectl delete role sync-agent-role -n rbac-broken --ignore-not-found=true
kubectl delete serviceaccount sync-agent -n rbac-broken --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sync-agent
  namespace: rbac-broken
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: sync-agent-role
  namespace: rbac-broken
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch", "update"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: sync-agent-binding
  namespace: rbac-broken
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: sync-agent-role
subjects:
- kind: ServiceAccount
  name: sync-agent
  namespace: default
YAML

echo "Setup completed for Question 11"
