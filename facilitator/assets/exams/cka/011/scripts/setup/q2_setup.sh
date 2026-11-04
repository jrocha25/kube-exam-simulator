#!/bin/bash
set -e

# Question 2: a Helm release taken through an upgrade.
#
# The chart is written to disk here rather than pulled from a repository, so the
# question needs no network at exam time and does not repeat cka/005 q12, which
# is about adding a public repo. Any release left by a previous attempt is
# removed so "helm install" is not met with an existing release.

NAMESPACE="ops-charts"
CHART="/tmp/exam/q2/beacon-chart"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
helm uninstall beacon -n "$NAMESPACE" >/dev/null 2>&1 || true

rm -rf "$CHART"
mkdir -p "${CHART}/templates"

cat > "${CHART}/Chart.yaml" <<'YAML'
apiVersion: v2
name: beacon-chart
description: Approach beacon status publisher
type: application
version: 1.0.0
appVersion: "1.0.0"
YAML

cat > "${CHART}/values.yaml" <<'YAML'
replicaCount: 1
message: standby
image: nginx:1.27.4
YAML

cat > "${CHART}/templates/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: beacon
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      app: beacon
  template:
    metadata:
      labels:
        app: beacon
    spec:
      containers:
      - name: beacon
        image: {{ .Values.image }}
        env:
        - name: BEACON_MESSAGE
          value: "{{ .Values.message }}"
YAML

echo "Setup completed for Question 2"
