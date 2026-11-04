#!/bin/bash
set -e

# Question 6: an autoscaler that can never compute a utilisation percentage,
# because its target declares no CPU request to compute it against.
kubectl create namespace scale-batch --dry-run=client -o yaml | kubectl apply -f -

kubectl delete horizontalpodautoscaler render-worker-hpa -n scale-batch --ignore-not-found=true
kubectl delete deployment render-worker -n scale-batch --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: render-worker
  namespace: scale-batch
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
      - name: worker
        image: nginx:1.27.4
        ports:
        - containerPort: 80
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: render-worker-hpa
  namespace: scale-batch
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: render-worker
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 60
YAML

kubectl rollout status deployment/render-worker -n scale-batch --timeout=180s || true

echo "Setup completed for Question 6"
