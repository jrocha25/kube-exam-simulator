#!/bin/bash
set -e

# Question 13: grow a bound claim in place. The admission plugin rejects any
# request increase unless the claim's StorageClass sets allowVolumeExpansion --
# the one mutable field of a StorageClass -- so that is the change the cluster
# requires. local-path has no resizer: the claim then sits with an
# ExternalExpanding event and status.capacity stays at 256Mi, which the
# question says up front. Record the claim's identity and the data's checksum.

NAMESPACE="stor-ledger"
SC="harbor-grow"
STATE_DIR=/tmp/exam/q13

mkdir -p "$STATE_DIR"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

TOKEN=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')

kubectl apply -f - <<YAML
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: $SC
provisioner: rancher.io/local-path
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ledger-data
  namespace: $NAMESPACE
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: $SC
  resources:
    requests:
      storage: 256Mi
YAML

if ! kubectl get pod ledger-writer -n "$NAMESPACE" >/dev/null 2>&1; then
    kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: ledger-writer
  namespace: $NAMESPACE
spec:
  nodeSelector:
    ck-x.io/alias: node01
  containers:
  - name: writer
    image: busybox:1.36
    command: ["sh", "-c", "[ -s /data/ledger.txt ] || echo $TOKEN > /data/ledger.txt; exec sleep 2147483647"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: ledger-data
YAML
fi

kubectl wait --for=condition=Ready pod/ledger-writer -n "$NAMESPACE" --timeout=120s >/dev/null \
    || echo "WARNING: ledger-writer did not become ready"

kubectl exec -n "$NAMESPACE" ledger-writer -- cat /data/ledger.txt 2>/dev/null | sha256sum | awk '{print $1}' > "$STATE_DIR/data.sha256"
kubectl get pvc ledger-data -n "$NAMESPACE" -o jsonpath='{.metadata.uid} {.spec.volumeName}' > "$STATE_DIR/claim"

echo "Setup completed for Question 13"
