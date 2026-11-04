#!/bin/bash
set -e

# Question 2: deployment that has to be scaled and rolled to a new image
kubectl create namespace media --dry-run=client -o yaml | kubectl apply -f -

kubectl delete deployment media-api -n media --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: media-api
  namespace: media
spec:
  replicas: 1
  selector:
    matchLabels:
      app: media-api
  template:
    metadata:
      labels:
        app: media-api
    spec:
      containers:
      - name: api
        image: nginx:1.25
        ports:
        - containerPort: 80
EOF

kubectl rollout status deployment/media-api -n media --timeout=180s || true

echo "Setup completed for Question 2"
