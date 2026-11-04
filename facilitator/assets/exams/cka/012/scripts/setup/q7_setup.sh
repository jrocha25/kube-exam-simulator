#!/bin/bash
set -e

# Question 7: a Service with no endpoints.
#
# Two faults, both of them the kind that reads as plausible:
#
#   * the selector matches the Deployment object's OWN labels (component,
#     managed-by) rather than its Pod template's (app, tier). That is the mistake
#     behind a hand-written Service, and it selects nothing without looking wrong.
#   * targetPort names "metrics", a port the container never declares, so even a
#     corrected selector still produces no working path.
#
# The Deployment is untouchable, so the whole repair is on the Service. Its spec
# is fingerprinted here and compared at validation time: editing the Deployment's
# labels would be a much easier way to pass s1.

NAMESPACE="svc-catalog"
DEPLOYMENT="station-catalog"
DIR="/tmp/exam/q7"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl delete service station-catalog-svc -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true

kubectl apply -f - <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: station-catalog
  namespace: svc-catalog
  labels:
    component: station-catalog
    managed-by: data-team
spec:
  replicas: 3
  selector:
    matchLabels:
      app: station-catalog
      tier: api
  template:
    metadata:
      labels:
        app: station-catalog
        tier: api
    spec:
      containers:
      - name: catalog
        image: nginx:1.27.4
        ports:
        - name: web
          containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: station-catalog-svc
  namespace: svc-catalog
spec:
  type: ClusterIP
  selector:
    component: station-catalog
    managed-by: data-team
  ports:
  - protocol: TCP
    port: 80
    targetPort: metrics
---
apiVersion: v1
kind: Pod
metadata:
  name: catalog-probe
  namespace: svc-catalog
  labels:
    app: catalog-probe
spec:
  containers:
  - name: probe
    image: nginx:1.27.4
YAML

kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=150s \
    || echo "WARNING: ${DEPLOYMENT} did not become ready"
kubectl wait --for=condition=Ready pod/catalog-probe -n "$NAMESPACE" --timeout=120s \
    || echo "WARNING: the catalog-probe Pod did not become ready"

# Fingerprint the Deployment as it stands now. Re-recording on every warm-up is
# what keeps the constraint honest across repeated attempts.
mkdir -p "$DIR"
rm -f "${DIR}/deployment.sha" "${DIR}/deployment.generation"
kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json 2>/dev/null \
    | jq -S '.spec' | sha256sum | awk '{print $1}' > "${DIR}/deployment.sha" || true
kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
    -o jsonpath='{.metadata.generation}' 2>/dev/null > "${DIR}/deployment.generation" || true

echo "Setup completed for Question 7"
