#!/bin/bash
set -e

# Question 9: StatefulSet PVC retention across a scale-in.
#
# The StatefulSet is staged WITHOUT a persistentVolumeClaimRetentionPolicy, so
# its default (Retain on both scale and delete) is what the candidate has to
# change. Everything is torn down first, claims included: a previous attempt
# that already scaled to one replica and deleted the claims would hand over two
# of this question's three checks.

NAMESPACE="wl-baggage"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl delete statefulset belt -n "$NAMESPACE" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
kubectl delete pvc -n "$NAMESPACE" -l app=belt --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
for i in 0 1 2; do
    kubectl delete pvc "data-belt-${i}" -n "$NAMESPACE" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
done

kubectl apply -f - <<YAML
apiVersion: v1
kind: Service
metadata:
  name: belt
  namespace: $NAMESPACE
spec:
  clusterIP: None
  selector:
    app: belt
  ports:
  - port: 80
    name: http
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: belt
  namespace: $NAMESPACE
spec:
  serviceName: belt
  replicas: 3
  selector:
    matchLabels:
      app: belt
  template:
    metadata:
      labels:
        app: belt
    spec:
      containers:
      - name: belt
        image: nginx:1.27.4
        ports:
        - containerPort: 80
        volumeMounts:
        - name: data
          mountPath: /var/belt
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes:
      - ReadWriteOnce
      resources:
        requests:
          storage: 1Gi
YAML

kubectl rollout status statefulset/belt -n "$NAMESPACE" --timeout=180s \
    || echo "WARNING: the belt StatefulSet did not reach 3 ready replicas"

echo "Setup completed for Question 9"
