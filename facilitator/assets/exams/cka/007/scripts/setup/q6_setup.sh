#!/bin/bash
set -e

# Question 6: an over broad authorization estate to narrow. "legacy-access" binds
# one Role to three subjects that now need three different things, which is the
# split the candidate has to perform; ops-readonly and deploy-managers are the
# neighbours that have to survive it untouched.
kubectl create namespace rbac-review --dry-run=client -o yaml | kubectl apply -f -

kubectl delete rolebinding legacy-access ops-readonly deploy-managers -n rbac-review --ignore-not-found=true
kubectl delete role legacy-writer ops-viewer -n rbac-review --ignore-not-found=true
kubectl delete serviceaccount legacy-svc ops-bot -n rbac-review --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: v1
kind: ServiceAccount
metadata:
  name: legacy-svc
  namespace: rbac-review
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ops-bot
  namespace: rbac-review
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: legacy-writer
  namespace: rbac-review
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "create", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: ops-viewer
  namespace: rbac-review
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: legacy-access
  namespace: rbac-review
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: legacy-writer
subjects:
- kind: ServiceAccount
  name: legacy-svc
  namespace: rbac-review
- kind: User
  name: hallie
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: legacy-operators
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: ops-readonly
  namespace: rbac-review
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: ops-viewer
subjects:
- kind: ServiceAccount
  name: ops-bot
  namespace: rbac-review
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: deploy-managers
  namespace: rbac-review
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: edit
subjects:
- kind: Group
  name: delivery-team
  apiGroup: rbac.authorization.k8s.io
YAML

echo "Setup completed for Question 6"
