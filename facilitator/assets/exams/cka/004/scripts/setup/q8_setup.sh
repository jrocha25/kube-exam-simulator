#!/bin/bash
set -e

# Question 8: application that writes a log file, ready for a sidecar
kubectl create namespace logistics --dry-run=client -o yaml | kubectl apply -f -

kubectl delete deployment shipment-tracker -n logistics --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shipment-tracker
  namespace: logistics
spec:
  replicas: 2
  selector:
    matchLabels:
      app: shipment-tracker
  template:
    metadata:
      labels:
        app: shipment-tracker
    spec:
      containers:
      - name: tracker
        image: busybox:1.36
        command:
        - /bin/sh
        - -c
        - "mkdir -p /var/log/app; while true; do echo \"\$(date) shipment scanned\" >> /var/log/app/tracker.log; sleep 5; done"
EOF

kubectl rollout status deployment/shipment-tracker -n logistics --timeout=180s || true

echo "Setup completed for Question 8"
