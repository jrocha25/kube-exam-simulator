#!/bin/bash
set -e

# Question 10: the backup account was granted cluster-admin "temporarily" and
# never walked back. The work here is removing access, not adding it, so the
# validation grades effective permissions rather than object names.
kubectl create namespace rbac-excess --dry-run=client -o yaml | kubectl apply -f -

kubectl delete clusterrolebinding backup-agent-admin --ignore-not-found=true
kubectl delete clusterrolebinding backup-agent-pv-reader --ignore-not-found=true
kubectl delete clusterrole backup-pv-reader --ignore-not-found=true
kubectl delete rolebinding backup-agent-reader -n rbac-excess --ignore-not-found=true
kubectl delete role backup-reader -n rbac-excess --ignore-not-found=true
kubectl delete serviceaccount backup-agent -n rbac-excess --ignore-not-found=true

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: backup-agent
  namespace: rbac-excess
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backup-scratch
  namespace: rbac-excess
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 128Mi
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: backup-agent-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: backup-agent
  namespace: rbac-excess
YAML

echo "Setup completed for Question 10"
