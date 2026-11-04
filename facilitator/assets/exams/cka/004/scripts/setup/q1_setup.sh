#!/bin/bash
set -e

# Question 1: PersistentVolume left Released by a deleted PersistentVolumeClaim
kubectl create namespace archive --dry-run=client -o yaml | kubectl apply -f -

mkdir -p /tmp/exam/q1

# Remove any leftover objects the candidate is expected to create
kubectl delete deployment archive-api -n archive --ignore-not-found=true
kubectl delete pvc archive-pvc -n archive --ignore-not-found=true
kubectl delete pvc archive-old -n archive --ignore-not-found=true
kubectl delete pv archive-pv --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: archive-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: archive-manual
  hostPath:
    path: /mnt/archive-data
    type: DirectoryOrCreate
EOF

# Bind a claim to the volume and then delete it, so the PV is left in the
# Released phase with a stale claimRef pointing at an object that is gone.
kubectl apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: archive-old
  namespace: archive
spec:
  accessModes:
  - ReadWriteOnce
  storageClassName: archive-manual
  resources:
    requests:
      storage: 1Gi
EOF

for _ in $(seq 1 30); do
    PHASE=$(kubectl get pv archive-pv -o jsonpath='{.status.phase}' 2>/dev/null || true)
    if [ "$PHASE" = "Bound" ]; then
        break
    fi
    sleep 2
done

if [ "$PHASE" != "Bound" ]; then
    echo "WARNING: PersistentVolume archive-pv did not bind to archive-old in time"
fi

kubectl delete pvc archive-old -n archive --ignore-not-found=true

cat > /tmp/exam/q1/archive-deploy.yaml <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: archive-api
  namespace: archive
spec:
  replicas: 1
  selector:
    matchLabels:
      app: archive-api
  template:
    metadata:
      labels:
        app: archive-api
    spec:
      containers:
      - name: api
        image: nginx:1.27.4
        ports:
        - containerPort: 80
        volumeMounts:
        - name: archive-data
          mountPath: /usr/share/nginx/html/archive
      volumes:
      - name: archive-data
        persistentVolumeClaim:
          claimName: ""
EOF

echo "Setup completed for Question 1"
