#!/bin/bash
set -e

# Question 9: a PodDisruptionBudget and a drain. A legacy budget already covers
# the quorum Pods; the moment a second one does too, the eviction API refuses to
# evict any of them ("more than one PodDisruptionBudget") and kubectl drain
# retries forever. The candidate has to notice and leave exactly one budget.
#
# This script sorts last of all (q1, q10..q17, q2..q9), so nothing is created
# after node02 is uncordoned here: every other fixture is already in place and
# pinned elsewhere, and the drain never meets a Pod it cannot evict.

NAMESPACE="wl-quorum"
DEPLOYMENT="quorum"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

NODE02=$(grep '^node02=' /tmp/exam/nodes.env | cut -d= -f2)
[ -n "$NODE02" ] && kubectl uncordon "$NODE02" >/dev/null 2>&1 || true

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $DEPLOYMENT
  namespace: $NAMESPACE
  labels:
    app: quorum
spec:
  replicas: 3
  selector:
    matchLabels:
      app: quorum
      ring: primary
  template:
    metadata:
      labels:
        app: quorum
        ring: primary
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: ck-x.io/alias
                operator: In
                values: ["node01", "node02"]
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              topologyKey: kubernetes.io/hostname
              labelSelector:
                matchLabels:
                  app: quorum
      containers:
      - name: member
        image: nginx:1.27.4
        volumeMounts:
        - name: journal
          mountPath: /var/lib/quorum
      volumes:
      - name: journal
        emptyDir: {}
---
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: quorum-legacy
  namespace: $NAMESPACE
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: quorum
YAML

kubectl rollout status deployment/"$DEPLOYMENT" -n "$NAMESPACE" --timeout=120s \
    || echo "WARNING: $DEPLOYMENT did not become ready"

ON_NODE02=$(kubectl get pods -n "$NAMESPACE" -l app=quorum --field-selector "spec.nodeName=${NODE02}" -o name 2>/dev/null | wc -l)
[ "$ON_NODE02" -gt 0 ] || echo "WARNING: no quorum replica landed on node02; question 9's drain has nothing to evict"

echo "Setup completed for Question 9"
