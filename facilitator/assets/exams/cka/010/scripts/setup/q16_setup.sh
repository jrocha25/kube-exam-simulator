#!/bin/bash
set -e

# Question 16: a container that is OOMKilled on every start. The workload
# allocates a fixed ~40MB working set (a shell variable filled from /dev/zero)
# and then idles; its limit is 32Mi, so the kernel kills it before it ever gets
# to idle, and the kubelet restarts it into the same wall. "kubectl describe"
# shows the last state as OOMKilled and a climbing restart count.
#
# The approved limit, 128Mi, is stated in the question; the 40MB payload leaves
# comfortable room under it even with the shell's capture buffer counted.

NAMESPACE="ts-memory"
DEPLOYMENT="render-worker"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment "$DEPLOYMENT" -n "$NAMESPACE" --ignore-not-found=true

kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: render-worker
  namespace: ts-memory
  labels:
    app: render-worker
spec:
  replicas: 1
  selector:
    matchLabels:
      app: render-worker
  template:
    metadata:
      labels:
        app: render-worker
    spec:
      containers:
      - name: renderer
        image: busybox:1.36
        command:
        - sh
        - -c
        - 'echo "loading working set"; buf=$(head -c 40000000 /dev/zero | tr "\0" a); echo "ready"; while true; do sleep 3600; done'
        resources:
          requests:
            cpu: 50m
            memory: 16Mi
          limits:
            memory: 32Mi
YAML

echo "Setup completed for Question 16 (render-worker is OOMKilled, by design)"
