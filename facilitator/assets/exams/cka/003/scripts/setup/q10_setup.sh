#!/bin/bash
set -e

# Question 10: install a local Helm chart
kubectl create namespace helm-apps --dry-run=client -o yaml | kubectl apply -f -

helm uninstall webstack -n helm-apps 2>/dev/null || true

CHART_DIR="/tmp/exam/q10/webstack"
rm -rf /tmp/exam/q10
mkdir -p "$CHART_DIR/templates"

cat > "$CHART_DIR/Chart.yaml" <<EOF
apiVersion: v2
name: webstack
description: A minimal web stack chart used for CKA practice
type: application
version: 0.1.0
appVersion: "1.0"
EOF

cat > "$CHART_DIR/values.yaml" <<EOF
replicaCount: 1

image:
  repository: nginx
  tag: "1.26.3"
  pullPolicy: IfNotPresent
EOF

cat > "$CHART_DIR/templates/deployment.yaml" <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}-web
  labels:
    app: {{ .Release.Name }}-web
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: {{ .Release.Name }}-web
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}-web
    spec:
      containers:
      - name: web
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - containerPort: 80
EOF

echo "Setup completed for Question 10"
