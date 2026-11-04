#!/bin/bash
set -e

# Question 15: a rollout that cannot finish, for three reasons stacked so that
# each one hides the next.
#
#   1. The namespace quota allows exactly 2 Pods, and the Deployment's rolling
#      update wants to surge a third. The new ReplicaSet cannot create a single
#      Pod ("exceeded quota" on the ReplicaSet's events), so the old Pods keep
#      serving and nothing else is visible yet.
#   2. Once the strategy no longer surges, the new Pods fail to start: the
#      secretKeyRef names a key the Secret does not have (CreateContainerConfigError).
#   3. Once that is fixed, both probes check port 8080 where nginx serves 80, so
#      the Pods never become ready and the liveness probe keeps killing them.
#
# Revision 1 is healthy and runs before the quota exists, so the starting state
# is two good Pods and a rollout that never progresses -- not an outage.

NAMESPACE="ts-cargo"
DEPLOYMENT="cargo-api"
STATE_DIR=/tmp/exam/q15

mkdir -p "$STATE_DIR"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

TOKEN=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
kubectl create secret generic relay-secrets -n "$NAMESPACE" --from-literal=api-token="$TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
kubectl delete resourcequota cargo-quota -n "$NAMESPACE" --ignore-not-found=true

deployment() {
    local key="$1" port="$2" release="$3"
    kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT
  namespace: $NAMESPACE
  labels:
    app: $DEPLOYMENT
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $DEPLOYMENT
  template:
    metadata:
      labels:
        app: $DEPLOYMENT
    spec:
      nodeSelector:
        ck-x.io/alias: node01
      containers:
      - name: api
        image: nginx:1.27.4
        env:
        - name: RELEASE
          value: "$release"
        - name: API_TOKEN
          valueFrom:
            secretKeyRef:
              name: relay-secrets
              key: $key
        ports:
        - containerPort: 80
        readinessProbe:
          httpGet:
            path: /
            port: $port
          periodSeconds: 5
        livenessProbe:
          httpGet:
            path: /
            port: $port
          initialDelaySeconds: 5
          periodSeconds: 5
          failureThreshold: 3
YAML
}

deployment api-token 80 "2026.09"
kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=90s \
    || echo "WARNING: revision 1 of $DEPLOYMENT did not become ready"

kubectl apply -f - <<YAML
apiVersion: v1
kind: ResourceQuota
metadata:
  name: cargo-quota
  namespace: $NAMESPACE
spec:
  hard:
    pods: "2"
YAML

deployment API_TOKEN 8080 "2026.10"

kubectl get secret relay-secrets -n "$NAMESPACE" -o json | jq -c '{uid: .metadata.uid, data: .data}' | sha256sum > "$STATE_DIR/secret.sha256"
kubectl get resourcequota cargo-quota -n "$NAMESPACE" -o json | jq -c '{uid: .metadata.uid, hard: .spec.hard, scopes: .spec.scopes, scopeSelector: .spec.scopeSelector}' | sha256sum > "$STATE_DIR/quota.sha256"

echo "Setup completed for Question 15"
