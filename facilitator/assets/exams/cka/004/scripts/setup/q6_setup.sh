#!/bin/bash
set -e

# Question 6: three candidate NetworkPolicies, only one of them least permissive
kubectl create namespace ledger --dry-run=client -o yaml | kubectl apply -f -
kubectl create namespace ledger-clients --dry-run=client -o yaml | kubectl apply -f -

kubectl delete networkpolicy ledger-ingress -n ledger --ignore-not-found=true
kubectl delete deployment ledger -n ledger --ignore-not-found=true
kubectl delete deployment reporting -n ledger --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ledger
  namespace: ledger
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ledger
  template:
    metadata:
      labels:
        app: ledger
    spec:
      containers:
      - name: ledger
        image: nginx:1.27.4
        ports:
        - containerPort: 80
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: reporting
  namespace: ledger
spec:
  replicas: 1
  selector:
    matchLabels:
      app: reporting
  template:
    metadata:
      labels:
        app: reporting
    spec:
      containers:
      - name: reporting
        image: nginx:1.27.4
        ports:
        - containerPort: 80
EOF

rm -rf /tmp/exam/q6
mkdir -p /tmp/exam/q6/policies

cat > /tmp/exam/q6/policies/policy-a.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ledger-ingress
  namespace: ledger
spec:
  podSelector:
    matchLabels:
      app: ledger
  policyTypes:
  - Ingress
  ingress:
  - {}
EOF

cat > /tmp/exam/q6/policies/policy-b.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ledger-ingress
  namespace: ledger
spec:
  podSelector:
    matchLabels:
      app: ledger
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ledger-clients
    ports:
    - protocol: TCP
      port: 80
EOF

cat > /tmp/exam/q6/policies/policy-c.yaml <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: ledger-ingress
  namespace: ledger
spec:
  podSelector:
    matchLabels:
      app: ledger
  policyTypes:
  - Ingress
  ingress:
  - from:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 80
EOF

# Keep a pristine copy so the validation can prove the files were applied unmodified
mkdir -p /tmp/exam/q6/.pristine
cp /tmp/exam/q6/policies/policy-a.yaml /tmp/exam/q6/policies/policy-b.yaml /tmp/exam/q6/policies/policy-c.yaml /tmp/exam/q6/.pristine/

kubectl rollout status deployment/ledger -n ledger --timeout=180s || true

echo "Setup completed for Question 6"
