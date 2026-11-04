#!/bin/bash
set -e

# Question 13: a local chart whose Deployment template quotes the replica count,
# so what it renders is a string where the API server demands an integer. Helm
# itself is happy; the install dies on the apply.
kubectl create namespace helm-broken --dry-run=client -o yaml | kubectl apply -f -

helm uninstall orderbook -n helm-broken 2>/dev/null || true

rm -rf /tmp/exam/q13
mkdir -p /tmp/exam/q13/orderbook/templates

cat > /tmp/exam/q13/orderbook/Chart.yaml <<'YAML'
apiVersion: v2
name: orderbook
description: The Helioscale order book service
type: application
version: 1.2.0
appVersion: "1.2.0"
YAML

cat > /tmp/exam/q13/orderbook/values.yaml <<'YAML'
replicaCount: 3

image:
  repository: nginx
  tag: "1.27.4"
  pullPolicy: IfNotPresent

service:
  port: 80
YAML

cat > /tmp/exam/q13/orderbook/templates/deployment.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
  labels:
    app: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount | quote }}
  selector:
    matchLabels:
      app: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}
    spec:
      containers:
      - name: orderbook
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        imagePullPolicy: {{ .Values.image.pullPolicy }}
        ports:
        - containerPort: 80
YAML

cat > /tmp/exam/q13/orderbook/templates/service.yaml <<'YAML'
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
YAML

echo "Setup completed for Question 13"
