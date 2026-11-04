#!/bin/bash
set -e

# Question 3: resource requests far above node capacity -> Pods stay Pending
kubectl create namespace analytics --dry-run=client -o yaml | kubectl apply -f -

kubectl delete deployment report-builder -n analytics --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: report-builder
  namespace: analytics
spec:
  replicas: 3
  selector:
    matchLabels:
      app: report-builder
  template:
    metadata:
      labels:
        app: report-builder
    spec:
      containers:
      - name: builder
        image: nginx:1.27.4
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: "256"
            memory: 512Gi
          limits:
            cpu: "512"
            memory: 1024Gi
EOF

echo "Setup completed for Question 3"
