#!/bin/bash
set -e

# Question 15: an autoscaler added through Kustomize, and a ConfigMap taken out.
#
# The ConfigMap is referenced by a patch in BOTH overlays, so removing it from
# the base alone makes "kubectl kustomize" fail with "no resource matches
# strategic merge patch" -- the loud half of the task. The quiet half is that
# Kustomize keeps no state, so deleting the ConfigMap from the configuration
# never deletes the copies already in the cluster; those have to go by hand.

NAMESPACE_STAGING="kustom-flight-staging"
NAMESPACE_PROD="kustom-flight-prod"
ROOT="/tmp/exam/q15/flightboard"

for ns in "$NAMESPACE_STAGING" "$NAMESPACE_PROD"; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
    kubectl delete horizontalpodautoscaler flightboard -n "$ns" --ignore-not-found=true >/dev/null 2>&1 || true
done

rm -rf "$ROOT"
mkdir -p "${ROOT}/base" "${ROOT}/staging" "${ROOT}/prod"

cat > "${ROOT}/base/kustomization.yaml" <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- flightboard.yaml
YAML

cat > "${ROOT}/base/flightboard.yaml" <<'YAML'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: flightboard
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: refresh-config
data:
  refresh-seconds: "90"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flightboard
spec:
  replicas: 1
  selector:
    matchLabels:
      id: flightboard
  template:
    metadata:
      labels:
        id: flightboard
    spec:
      serviceAccountName: flightboard
      containers:
      - name: board
        image: nginx:1.27.4
        resources:
          requests:
            cpu: 10m
            memory: 20Mi
YAML

for env in staging prod; do
    case "$env" in
        staging) ns="$NAMESPACE_STAGING"; refresh="60" ;;
        prod)    ns="$NAMESPACE_PROD";    refresh="30" ;;
    esac

    cat > "${ROOT}/${env}/kustomization.yaml" <<YAML
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: ${ns}

resources:
- ../base

patches:
- path: flightboard.yaml
YAML

    cat > "${ROOT}/${env}/flightboard.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: refresh-config
data:
  refresh-seconds: "${refresh}"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: flightboard
  labels:
    env: ${env}
YAML
done

# Put both overlays live, exactly the way the question says they were deployed.
for env in staging prod; do
    if ! kubectl kustomize "${ROOT}/${env}" | kubectl apply -f - >/dev/null; then
        echo "WARNING: could not apply the ${env} overlay"
    fi
done

for ns in "$NAMESPACE_STAGING" "$NAMESPACE_PROD"; do
    kubectl rollout status deployment/flightboard -n "$ns" --timeout=120s \
        || echo "WARNING: the flightboard Deployment in ${ns} did not become ready"
done

echo "Setup completed for Question 15"
