#!/bin/bash
set -e

# Question 5: a retained PersistentVolume left Released by a deleted claim. Its
# stale claimRef keeps it from binding again until somebody clears it, and the
# default StorageClass is injected into any claim that does not name one.

NAMESPACE="ledger"
PV="ledger-pv"
PVC="ledger-data"
SC="ledger-manual"
DATA_DIR=/srv/ck-x/ledger
WORKDIR=/tmp/exam/q5
STATE=/tmp/exam/.q5

mkdir -p "$WORKDIR" "$STATE"

NODE01=$(grep '^node01=' /tmp/exam/nodes.env | cut -d= -f2)
if [ -z "$NODE01" ] || [ -f /tmp/exam/node-ssh-unavailable ]; then
    echo "WARNING: no shell on node01, question 5 cannot be staged"
    exit 0
fi

TOKEN="ledger-$(head -c 12 /dev/urandom | od -An -tx1 | tr -d ' \n')"
echo "$TOKEN" > "$STATE/token"
ssh -o ConnectTimeout=10 node01 "mkdir -p $DATA_DIR && echo '$TOKEN' > $DATA_DIR/ledger.token"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment ledger-db -n "$NAMESPACE" --ignore-not-found=true --wait=true
kubectl delete pvc "$PVC" -n "$NAMESPACE" --ignore-not-found=true --wait=true

kubectl apply -f - <<YAML
apiVersion: v1
kind: PersistentVolume
metadata:
  name: $PV
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: $SC
  hostPath:
    path: $DATA_DIR
    type: Directory
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values:
          - $NODE01
YAML

# Bind it once, then delete the claim: the PV goes Released and keeps the old
# claim's uid in spec.claimRef.
kubectl apply -f - <<YAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: $PVC
  namespace: $NAMESPACE
spec:
  storageClassName: $SC
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
YAML
for _ in $(seq 1 12); do
    [ "$(kubectl get pvc "$PVC" -n "$NAMESPACE" -o jsonpath='{.status.phase}')" = "Bound" ] && break
    sleep 5
done
kubectl delete pvc "$PVC" -n "$NAMESPACE" --wait=true
for _ in $(seq 1 12); do
    [ "$(kubectl get pv "$PV" -o jsonpath='{.status.phase}')" = "Released" ] && break
    sleep 5
done
[ "$(kubectl get pv "$PV" -o jsonpath='{.status.phase}')" = "Released" ] \
    || echo "WARNING: $PV is not Released"
kubectl get pv "$PV" -o jsonpath='{.metadata.uid}' > "$STATE/pv.uid"

cat > "$WORKDIR/ledger-db.yaml" <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ledger-db
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ledger-db
  template:
    metadata:
      labels:
        app: ledger-db
    spec:
      containers:
      - name: db
        image: busybox:1.36
        command: ["sh", "-c", "cat /var/lib/ledger/ledger.token && exec sleep 2147483647"]
        volumeMounts:
        - name: ledger
          mountPath: /var/lib/ledger
      volumes:
      - name: ledger
        persistentVolumeClaim:
          claimName: $PVC
YAML

echo "Setup for question 5 completed"
