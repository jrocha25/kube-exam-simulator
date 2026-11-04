#!/bin/bash
set -e

# Question 5: a deterministic CPU hog to be found with kubectl top
kubectl create namespace loadgen --dry-run=client -o yaml | kubectl apply -f -

mkdir -p /tmp/exam/q5
rm -f /tmp/exam/q5/top-pod.txt /tmp/exam/q5/top-node.txt

kubectl delete deployment cpu-hog -n loadgen --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: cpu-hog
  namespace: loadgen
spec:
  replicas: 1
  selector:
    matchLabels:
      app: cpu-hog
  template:
    metadata:
      labels:
        app: cpu-hog
    spec:
      containers:
      - name: burner
        image: busybox:1.36
        command:
        - /bin/sh
        - -c
        - "while true; do :; done"
        resources:
          requests:
            cpu: 200m
            memory: 32Mi
          limits:
            cpu: "1"
            memory: 64Mi
EOF

kubectl rollout status deployment/cpu-hog -n loadgen --timeout=180s || true

echo "Setup completed for Question 5"
