#!/bin/bash
set -e

# Question 16: rotating an immutable ConfigMap. "kubectl edit" cannot do it -- an
# immutable ConfigMap rejects every update -- and neither can delete-and-recreate
# under the same name: marking a ConfigMap immutable tells every kubelet it may
# stop watching the object, so a node that already cached this one keeps handing
# the old values to new Pods forever. The supported route is a new object under a
# new name with the consumers repointed at it, which is what the question asks for
# and what the verification checks.
#
# The Deployment is deliberately already running against the old values, so a
# candidate who creates the new ConfigMap but never rolls the Pods still has the
# previous environment running -- and a verification step reads the environment
# out of a running pod, not out of the ConfigMap.

NAMESPACE="config-rotate"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment feature-api -n "$NAMESPACE" --ignore-not-found=true
kubectl delete configmap feature-flags feature-flags-v2 -n "$NAMESPACE" --ignore-not-found=true

kubectl apply -f - <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: feature-flags
  namespace: $NAMESPACE
immutable: true
data:
  RELEASE_CHANNEL: "beta"
  MAX_BATCH_SIZE: "50"
YAML

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: feature-api
  namespace: $NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: feature-api
  template:
    metadata:
      labels:
        app: feature-api
    spec:
      containers:
      - name: api
        image: nginx:1.27.4
        envFrom:
        - configMapRef:
            name: feature-flags
        ports:
        - containerPort: 80
YAML

kubectl rollout status deployment/feature-api -n "$NAMESPACE" --timeout=180s \
    || echo "WARNING: feature-api did not become ready in time"

echo "Setup completed for Question 16"
