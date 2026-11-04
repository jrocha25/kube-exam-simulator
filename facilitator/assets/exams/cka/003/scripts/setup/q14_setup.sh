#!/bin/bash
set -e

# Question 14: envFrom pointing at a ConfigMap that does not exist
kubectl create namespace ts-config --dry-run=client -o yaml | kubectl apply -f -

kubectl delete deployment payments-worker -n ts-config --ignore-not-found=true
kubectl delete configmap payments-config -n ts-config --ignore-not-found=true

kubectl create configmap payments-cfg -n ts-config \
  --from-literal=PAYMENT_MODE=live \
  --from-literal=RETRY_COUNT=3 \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: payments-worker
  namespace: ts-config
spec:
  replicas: 2
  selector:
    matchLabels:
      app: payments-worker
  template:
    metadata:
      labels:
        app: payments-worker
    spec:
      containers:
      - name: worker
        image: busybox:1.36
        command: ["sh", "-c", "while true; do sleep 30; done"]
        envFrom:
        - configMapRef:
            name: payments-config
EOF

echo "Setup completed for Question 14"
