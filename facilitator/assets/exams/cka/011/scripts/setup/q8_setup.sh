#!/bin/bash
set -e

# Question 8: which of two identical-looking volumes a claim binds to.
#
# Both PVs offer the same capacity and access mode, so capacity cannot decide
# it and the claim has to select on labels. kind ships a default StorageClass
# ("standard", local-path), which is the trap here: a claim that omits
# storageClassName gets that class injected by admission and is dynamically
# provisioned instead of binding to either of these. The claim has to ask for
# no class at all.

NAMESPACE="stor-cargo"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Order matters: a bound PV cannot be re-created, and a PV left Released by a
# previous attempt will never bind again.
kubectl delete pvc cargo-claim -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true
kubectl delete deployment cargo-hold -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true
kubectl delete pv cargo-fast cargo-slow --ignore-not-found=true >/dev/null 2>&1 || true

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: PersistentVolume
metadata:
  name: cargo-fast
  labels:
    tier: fast
spec:
  capacity:
    storage: 5Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath:
    path: /mnt/cargo-fast
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: cargo-slow
  labels:
    tier: slow
spec:
  capacity:
    storage: 5Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: ""
  hostPath:
    path: /mnt/cargo-slow
    type: DirectoryOrCreate
YAML

echo "Setup completed for Question 8"
