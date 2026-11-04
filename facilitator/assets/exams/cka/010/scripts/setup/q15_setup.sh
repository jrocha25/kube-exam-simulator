#!/bin/bash
set -e

# Question 15: a claim that can never bind. The PersistentVolume is fine; the
# claim asks for an access mode the volume does not offer (ReadWriteMany
# against a ReadWriteOnce volume) and names a StorageClass that does not exist,
# so it is neither matched to archive-pv nor dynamically provisioned. Both
# have to be found by comparing the two objects, and the fix means recreating
# the claim, since those fields are immutable.
#
# The PV's spec is fingerprinted so q15_s2 can tell that the candidate repaired
# the claim rather than the volume. claimRef is excluded: binding sets it.

NAMESPACE="ts-storage"
PV="archive-pv"
PVC="archive-claim"
POD="archive-reader"

mkdir -p /tmp/exam/q15
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found=true --wait=false
kubectl delete pvc "$PVC" -n "$NAMESPACE" --ignore-not-found=true
kubectl delete pv "$PV" --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $PV
  labels:
    tier: archive
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: archive
  hostPath:
    path: /tmp/exam-archive
    type: DirectoryOrCreate
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC
  namespace: $NAMESPACE
spec:
  accessModes:
  - ReadWriteMany
  storageClassName: archive-old
  resources:
    requests:
      storage: 1Gi
---
apiVersion: v1
kind: Pod
metadata:
  name: $POD
  namespace: $NAMESPACE
spec:
  containers:
  - name: reader
    image: nginx:1.27.4
    volumeMounts:
    - name: archive
      mountPath: /archive
  volumes:
  - name: archive
    persistentVolumeClaim:
      claimName: $PVC
YAML

kubectl get pv "$PV" -o json | jq -S 'del(.spec.claimRef) | .spec' | sha256sum | cut -d' ' -f1 \
    > /tmp/exam/q15/pv-spec.sha

echo "Setup completed for Question 15 (archive-claim cannot bind, by design)"
