#!/bin/bash
set -e

# Question 10: a local Helm chart, installed / upgraded / rolled back by the candidate
kubectl create namespace edge-helm --dry-run=client -o yaml | kubectl apply -f -

helm uninstall web-edge -n edge-helm --ignore-not-found 2>/dev/null || true

rm -rf /tmp/exam/q10
mkdir -p /tmp/exam/q10/helioscale-web/templates

cat > /tmp/exam/q10/helioscale-web/Chart.yaml <<EOF
apiVersion: v2
name: helioscale-web
description: The Helioscale public web tier
type: application
version: 1.0.0
appVersion: "1.0.0"
EOF

cat > /tmp/exam/q10/helioscale-web/values.yaml <<EOF
replicaCount: 1

image:
  repository: nginx
  tag: "1.27.4"
  pullPolicy: IfNotPresent

service:
  port: 80
EOF

cat > /tmp/exam/q10/helioscale-web/templates/deployment.yaml <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
  labels:
    app: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}
    spec:
      containers:
      - name: web
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - containerPort: 80
EOF

cat > /tmp/exam/q10/helioscale-web/templates/service.yaml <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}
spec:
  type: ClusterIP
  selector:
    app: {{ .Release.Name }}
  ports:
  - protocol: TCP
    port: {{ .Values.service.port }}
    targetPort: 80
EOF

echo "Setup completed for Question 10"
