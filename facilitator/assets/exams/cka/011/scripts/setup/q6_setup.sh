#!/bin/bash
set -e

# Question 6: a second cluster DNS domain, staged on the AUXILIARY cluster.
#
# Rewriting the Corefile is a cluster-wide change: a typo takes name resolution
# down for everything running at the time. On the lab's own cluster that would
# constrain every other question's prompt and validation -- the mistake cka/006
# shipped and CLAUDE.md now warns about -- so this one is set next door, where a
# broken Corefile costs the candidate this question and nothing else.
#
# This is one of the two places a script is allowed to set KUBECONFIG itself.
export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

NAMESPACE="dns-tower"
DOMAIN="airops.internal"
DIR="/tmp/exam/q6"

mkdir -p "$DIR"
rm -f "${DIR}/coredns-backup.yaml"

if [ -f /tmp/exam/aux-cluster-unavailable ]; then
    echo "WARNING: the auxiliary cluster is unavailable, skipping setup for question 6"
    exit 0
fi

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: tower
  namespace: $NAMESPACE
spec:
  replicas: 1
  selector:
    matchLabels:
      app: tower
  template:
    metadata:
      labels:
        app: tower
    spec:
      containers:
      - name: tower
        image: nginx:1.27.4
        ports:
        - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: tower
  namespace: $NAMESPACE
spec:
  selector:
    app: tower
  ports:
  - port: 80
    targetPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: probe
  namespace: $NAMESPACE
spec:
  containers:
  - name: probe
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
YAML

# Undo a previous attempt's answer, if the Corefile still carries the domain.
if kubectl get configmap coredns -n kube-system -o jsonpath='{.data.Corefile}' 2>/dev/null | grep -q "$DOMAIN"; then
    echo "removing a leftover ${DOMAIN} entry from the Corefile"
    kubectl get configmap coredns -n kube-system -o json \
        | python3 -c '
import json, re, sys
doc = json.load(sys.stdin)
doc["data"]["Corefile"] = re.sub(r"[ \t]+airops\.internal\b", "", doc["data"]["Corefile"])
json.dump(doc, sys.stdout)
' \
        | kubectl apply -f - >/dev/null
    kubectl rollout restart deployment/coredns -n kube-system >/dev/null
    kubectl rollout status deployment/coredns -n kube-system --timeout=120s >/dev/null \
        || echo "WARNING: CoreDNS did not roll out cleanly after the revert"
fi

kubectl wait --for=condition=Ready pod/probe -n "$NAMESPACE" --timeout=120s \
    || echo "WARNING: the probe Pod on the auxiliary cluster did not become ready"

echo "Setup completed for Question 6"
