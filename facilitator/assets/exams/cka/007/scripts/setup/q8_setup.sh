#!/bin/bash
set -e

# Question 8: the ServiceAccount, Role and RoleBinding are all correct. The
# Deployment's pod template simply never names the account, so every replica
# runs as 'default' and the grant applies to an identity nothing runs as.
# The container really does call the API, so `kubectl logs` shows the 403.
kubectl create namespace rbac-identity --dry-run=client -o yaml | kubectl apply -f -

kubectl delete deployment inventory-sync -n rbac-identity --ignore-not-found=true
kubectl delete rolebinding inventory-sync-binding -n rbac-identity --ignore-not-found=true
kubectl delete role inventory-sync-role -n rbac-identity --ignore-not-found=true
kubectl delete serviceaccount inventory-sync -n rbac-identity --ignore-not-found=true

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: inventory-sync
  namespace: rbac-identity
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: inventory-state
  namespace: rbac-identity
data:
  last_sync: "never"
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: inventory-sync-role
  namespace: rbac-identity
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  verbs: ["get", "list", "watch", "update"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: inventory-sync-binding
  namespace: rbac-identity
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: inventory-sync-role
subjects:
- kind: ServiceAccount
  name: inventory-sync
  namespace: rbac-identity
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inventory-sync
  namespace: rbac-identity
spec:
  replicas: 2
  selector:
    matchLabels:
      app: inventory-sync
  template:
    metadata:
      labels:
        app: inventory-sync
    spec:
      containers:
      - name: sync
        image: curlimages/curl:8.11.1
        command:
        - /bin/sh
        - -c
        - |
          SA_DIR=/var/run/secrets/kubernetes.io/serviceaccount
          API=https://kubernetes.default.svc/api/v1/namespaces/rbac-identity/configmaps
          sleep 5
          while true; do
            echo "[sync] reconciling configmaps in rbac-identity"
            CODE=$(curl -s -o /tmp/body -w '%{http_code}' --cacert "$SA_DIR/ca.crt" \
                     -H "Authorization: Bearer $(cat $SA_DIR/token)" "$API")
            if [ "$CODE" = "200" ]; then
              echo "[sync] ok: inventory-state read"
            else
              echo "[sync] ERROR: HTTP $CODE from the API server"
              if [ -s /tmp/body ]; then
                tr -d '\n' < /tmp/body | tr -s ' ' | cut -c1-400
                echo
              fi
            fi
            sleep 15
          done
YAML

echo "Setup completed for Question 8"
