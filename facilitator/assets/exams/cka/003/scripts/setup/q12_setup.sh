#!/bin/bash
set -e

# Question 12: node maintenance with cordon and drain
kubectl create namespace drain-lab --dry-run=client -o yaml | kubectl apply -f -

# Make sure the maintenance node starts schedulable
kubectl uncordon k3d-cluster-agent-1 || true

# Reserve the maintenance node for legacy-app so that no other question's
# workload can be scheduled there and destroyed by the drain
kubectl taint nodes k3d-cluster-agent-1 maintenance=reserved:NoSchedule --overwrite

kubectl delete deployment legacy-app -n drain-lab --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: legacy-app
  namespace: drain-lab
spec:
  replicas: 3
  selector:
    matchLabels:
      app: legacy-app
  template:
    metadata:
      labels:
        app: legacy-app
    spec:
      nodeSelector:
        kubernetes.io/hostname: k3d-cluster-agent-1
      tolerations:
      - key: maintenance
        operator: Equal
        value: reserved
        effect: NoSchedule
      containers:
      - name: web
        image: nginx:1.27.4
        ports:
        - containerPort: 80
EOF

kubectl rollout status deployment/legacy-app -n drain-lab --timeout=180s || true

echo "Setup completed for Question 12"
