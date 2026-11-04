#!/bin/bash
set -e

# Question 17: liveness probe pointing at a path and port that do not exist
kubectl create namespace ts-probe --dry-run=client -o yaml | kubectl apply -f -

kubectl delete deployment frontend -n ts-probe --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: frontend
  namespace: ts-probe
spec:
  replicas: 2
  selector:
    matchLabels:
      app: frontend
  template:
    metadata:
      labels:
        app: frontend
    spec:
      containers:
      - name: web
        image: nginx:1.27.4
        ports:
        - containerPort: 80
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 10
EOF

echo "Setup completed for Question 17"
