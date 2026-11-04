#!/bin/bash

set -e

# Question 11: troubleshooting. Every replica sits Pending because the workload
# requires a node-class value no node in the cluster carries.
#
# The tempting repair is to label a node "archive" and move on. The question
# forbids touching node labels and a validation step checks them, so the real
# answer is to bring the workload back onto an approved class. The prompt names
# the approved values as context and never mentions node affinity, per the
# troubleshooting rules in CLAUDE.md.
#
# No wait here: these pods are supposed to be Pending, and waiting on them would
# just add 120s to every candidate's warm-up.

NAMESPACE="ts-sched"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment --all -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: customs-broker
  namespace: ${NAMESPACE}
  labels:
    app: customs-broker
spec:
  replicas: 3
  selector:
    matchLabels:
      app: customs-broker
  template:
    metadata:
      labels:
        app: customs-broker
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node-class
                operator: In
                values:
                - archive
      containers:
      - name: broker
        image: nginx:1.27.4
        ports:
        - containerPort: 80
YAML

echo "Setup completed for Question 11"
