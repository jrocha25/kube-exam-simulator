#!/bin/bash
set -e

# Question 3: a Helm release whose last upgrade broke it.
#
#   revision 1  --set replicaCount=2,berth=north           works
#   revision 2  --reuse-values --set image.tag=<missing>   ImagePullBackOff
#
# The chart uses the Recreate strategy, so revision 2 really takes the
# application down instead of leaving the old Pods serving behind a stuck
# rollout. The candidate must roll back to 1 and then upgrade with
# --reuse-values: an upgrade without it silently drops replicaCount and berth,
# which is the trap the question is built on.

NAMESPACE="helm-tide"
RELEASE="tidewatch"
DIR=/tmp/exam/q3
CHART="$DIR/tidewatch"

mkdir -p "$CHART/templates"

cat > "$CHART/Chart.yaml" <<'YAML'
apiVersion: v2
name: tidewatch
description: Tide level monitor for the harbour berths
type: application
version: 0.3.1
appVersion: "1.27.4"
YAML

cat > "$CHART/values.yaml" <<'YAML'
replicaCount: 1
berth: south
season: summer
tier: standard
image:
  repository: nginx
  tag: "1.27.4"
YAML

cat > "$CHART/templates/deployment.yaml" <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ .Release.Name }}
  labels:
    app: {{ .Release.Name }}
spec:
  replicas: {{ .Values.replicaCount }}
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: {{ .Release.Name }}
  template:
    metadata:
      labels:
        app: {{ .Release.Name }}
    spec:
      nodeSelector:
        ck-x.io/alias: node01
      containers:
      - name: monitor
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        env:
        - name: BERTH
          value: {{ .Values.berth | quote }}
        - name: SEASON
          value: {{ .Values.season | quote }}
        - name: TIER
          value: {{ .Values.tier | quote }}
        ports:
        - containerPort: 80
YAML

cat > "$DIR/values-season.yaml" <<'YAML'
season: winter
YAML

helm uninstall "$RELEASE" -n "$NAMESPACE" --wait >/dev/null 2>&1 || true
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

helm install "$RELEASE" "$CHART" -n "$NAMESPACE" \
    --set replicaCount=2,berth=north --wait --timeout 90s \
    || echo "WARNING: revision 1 of $RELEASE did not become ready"

helm upgrade "$RELEASE" "$CHART" -n "$NAMESPACE" \
    --reuse-values --set image.tag=1.27.4-ck-x-broken \
    || echo "WARNING: the broken upgrade of $RELEASE failed to apply"

echo "Setup completed for Question 3"
