#!/bin/bash
set -e

# Question 16: pods left Pending by a node taint
kubectl create namespace ts-sched --dry-run=client -o yaml | kubectl apply -f -

kubectl delete deployment analytics -n ts-sched --ignore-not-found=true

kubectl taint nodes k3d-cluster-agent-0 workload=analytics:NoSchedule --overwrite

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: analytics
  namespace: ts-sched
spec:
  replicas: 3
  selector:
    matchLabels:
      app: analytics
  template:
    metadata:
      labels:
        app: analytics
    spec:
      nodeSelector:
        kubernetes.io/hostname: k3d-cluster-agent-0
      containers:
      - name: web
        image: nginx:1.27.4
        ports:
        - containerPort: 80
EOF

echo "Setup completed for Question 16"
