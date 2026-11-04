#!/bin/bash
set -e

# Question 14: a shared base that already generates its ConfigMap, so the overlay
# has to override a generator rather than just patch a plain resource.
kubectl create namespace kustom-app --dry-run=client -o yaml | kubectl apply -f -

kubectl delete deployment,service,configmap --all -n kustom-app --ignore-not-found=true

rm -rf /tmp/exam/q14
mkdir -p /tmp/exam/q14/base /tmp/exam/q14/overlays

cat > /tmp/exam/q14/base/deployment.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 1
  selector:
    matchLabels:
      app: web
  template:
    metadata:
      labels:
        app: web
    spec:
      containers:
      - name: web
        image: nginx:1.25
        ports:
        - containerPort: 80
        volumeMounts:
        - name: content
          mountPath: /usr/share/nginx/html
      volumes:
      - name: content
        configMap:
          name: web-content
YAML

cat > /tmp/exam/q14/base/service.yaml <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: web
spec:
  type: ClusterIP
  selector:
    app: web
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
YAML

cat > /tmp/exam/q14/base/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
configMapGenerator:
- name: web-content
  literals:
  - index.html=base
YAML

echo "Setup completed for Question 14"
