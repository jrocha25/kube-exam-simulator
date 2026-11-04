#!/bin/bash
set -e

# Question 1: a PersistentVolumeClaim that can never bind.
# The claim asks for the storage class "fast-nvme", which does not exist in this
# cluster, so the provisioner never picks it up and the Pod never gets its volume.
kubectl create namespace store-data --dry-run=client -o yaml | kubectl apply -f -

kubectl delete deployment ledger-api -n store-data --ignore-not-found=true
kubectl delete pvc ledger-data -n store-data --ignore-not-found=true --timeout=60s || true

kubectl apply -f - <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ledger-data
  namespace: store-data
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: fast-nvme
  resources:
    requests:
      storage: 1Gi
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ledger-api
  namespace: store-data
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ledger-api
  template:
    metadata:
      labels:
        app: ledger-api
    spec:
      containers:
      - name: api
        image: nginx:1.27.4
        ports:
        - containerPort: 80
        volumeMounts:
        - name: data
          mountPath: /var/lib/ledger
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: ledger-data
YAML

echo "Setup completed for Question 1"
