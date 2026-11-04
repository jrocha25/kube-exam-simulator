#!/bin/bash
set -e

# Question 1: a local Helm chart that templates a CRD the platform team already
# installed. Installing it with the CRD switched on fails with an ownership
# conflict, which is the point: the chart has to be told not to manage it.

NAMESPACE="helm-berth"
WORKDIR=/tmp/exam/q1
CRD_NAME="berths.ops.harbor.io"

mkdir -p "$WORKDIR/charts"
rm -rf "$WORKDIR/src" "$WORKDIR"/charts/*.tgz "$WORKDIR/berthwatch.yaml"

helm uninstall berthwatch -n "$NAMESPACE" >/dev/null 2>&1 || true
kubectl delete namespace "$NAMESPACE" --ignore-not-found=true --wait=false

CRD_SPEC=$(cat <<'YAML'
  group: ops.harbor.io
  names:
    kind: Berth
    listKind: BerthList
    plural: berths
    singular: berth
  scope: Namespaced
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              quay:
                type: string
              lengthMeters:
                type: integer
YAML
)

# The platform team's copy, labelled as theirs and owned by no Helm release.
kubectl apply -f - <<YAML
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: $CRD_NAME
  labels:
    app.kubernetes.io/managed-by: platform-team
spec:
$CRD_SPEC
YAML

build_chart() {
    local version=$1 image=$2
    local dir="$WORKDIR/src/berthwatch"
    rm -rf "$dir"
    mkdir -p "$dir/templates"
    cat > "$dir/Chart.yaml" <<YAML
apiVersion: v2
name: berthwatch
description: Watches berth occupancy for the harbor control room
type: application
version: $version
appVersion: "$version"
YAML
    cat > "$dir/values.yaml" <<YAML
replicaCount: 1
image: $image
crds:
  # Install the Berth CustomResourceDefinition together with the release.
  install: true
service:
  port: 80
YAML
    cat > "$dir/templates/crd.yaml" <<YAML
{{- if .Values.crds.install }}
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: $CRD_NAME
spec:
$CRD_SPEC
{{- end }}
YAML
    cat > "$dir/templates/deployment.yaml" <<'YAML'
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
      - name: watcher
        image: {{ .Values.image }}
        ports:
        - containerPort: 80
YAML
    cat > "$dir/templates/service.yaml" <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: {{ .Release.Name }}
spec:
  selector:
    app: {{ .Release.Name }}
  ports:
  - port: {{ .Values.service.port }}
    targetPort: 80
YAML
    helm package "$dir" -d "$WORKDIR/charts" >/dev/null
}

build_chart 0.6.4 nginx:1.25.5
build_chart 0.7.2 nginx:1.27.4
rm -rf "$WORKDIR/src"

ls "$WORKDIR/charts"
echo "Setup for question 1 completed"
