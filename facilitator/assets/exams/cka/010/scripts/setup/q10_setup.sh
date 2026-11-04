#!/bin/bash
set -e

# Question 10: StatefulSet with a headless Service and volumeClaimTemplates.
# Only the namespace is staged; the "standard" StorageClass the claims use is
# kind's local-path provisioner, which is there on every kind cluster.

NAMESPACE="sts-ledger"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete statefulset ledger-db -n "$NAMESPACE" --ignore-not-found=true
kubectl delete service ledger-db -n "$NAMESPACE" --ignore-not-found=true
kubectl delete pvc -n "$NAMESPACE" -l app=ledger-db --ignore-not-found=true

if ! kubectl get storageclass standard >/dev/null 2>&1; then
    echo "WARNING: there is no StorageClass named 'standard'; question 10's claims will not bind"
fi

echo "Setup completed for Question 10"
