#!/bin/bash
set -e

# Question 3: make the Metrics API work.
#
# kind ships no metrics-server, which is what makes this a real task rather than
# a lookup -- and its kubelets serve a certificate the cluster CA did not sign,
# so the stock manifest deploys cleanly and then never scrapes anything. The
# candidate has to notice that and deal with it on the metrics-server side.
#
# Setup installs nothing. It only puts the manifest where the question says it
# is and warms the image on every node, because "kubeadm upgrade"-style waiting
# for a pull is not what this question is testing.

NAMESPACE="ops-metrics"
DIR="/tmp/exam/q3"
MANIFEST="${DIR}/metrics-server.yaml"
LATEST_URL="https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
PINNED_URL="https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.7.2/components.yaml"

rm -f /tmp/exam/metrics-server-unavailable
mkdir -p "$DIR"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: radar-feed
  namespace: $NAMESPACE
spec:
  replicas: 2
  selector:
    matchLabels:
      app: radar-feed
  template:
    metadata:
      labels:
        app: radar-feed
    spec:
      containers:
      - name: feed
        image: nginx:1.27.4
        resources:
          requests:
            cpu: 10m
            memory: 24Mi
      - name: relay
        image: busybox:1.36
        command: ["sh", "-c", "while true; do sleep 30; done"]
        resources:
          requests:
            cpu: 10m
            memory: 16Mi
YAML

# ---------------------------------------------------------------------------
# Undo a previous attempt. A metrics-server the candidate already installed
# would hand them the whole question for free.
# ---------------------------------------------------------------------------
kubectl delete apiservice v1beta1.metrics.k8s.io --ignore-not-found=true >/dev/null 2>&1 || true
for kind in deployment service serviceaccount; do
    kubectl delete "$kind" metrics-server -n kube-system --ignore-not-found=true >/dev/null 2>&1 || true
done
kubectl delete clusterrolebinding metrics-server:system:auth-delegator system:metrics-server \
    --ignore-not-found=true >/dev/null 2>&1 || true
kubectl delete clusterrole system:metrics-server system:aggregated-metrics-reader \
    --ignore-not-found=true >/dev/null 2>&1 || true
kubectl delete rolebinding metrics-server-auth-reader -n kube-system \
    --ignore-not-found=true >/dev/null 2>&1 || true

# ---------------------------------------------------------------------------
# The manifest. Pinned first for reproducibility, latest as a fallback -- and a
# marker plus a warning if neither can be fetched, so the question degrades to
# something the candidate can read rather than a task with no input file.
# ---------------------------------------------------------------------------
rm -f "$MANIFEST"
for url in "$PINNED_URL" "$LATEST_URL"; do
    if curl -fsSL --max-time 60 -o "$MANIFEST" "$url" 2>/dev/null && grep -q "kind: APIService" "$MANIFEST"; then
        echo "fetched the metrics-server manifest from ${url}"
        break
    fi
    rm -f "$MANIFEST"
done

if [ ! -s "$MANIFEST" ]; then
    echo "unavailable" > /tmp/exam/metrics-server-unavailable
    echo "WARNING: could not download the metrics-server manifest."
    echo "WARNING: this jumphost has no route to github.com, so question 3 has no"
    echo "WARNING: input file and cannot be solved. The rest of the lab is unaffected."
else
    # The stock manifest must not already carry the flag that makes it work on
    # kind -- if upstream ever adds it, the question is a no-op and should be
    # restaged rather than silently score for free.
    if grep -q -- "--kubelet-insecure-tls" "$MANIFEST"; then
        echo "WARNING: the upstream manifest already tolerates the kubelet certificates."
        echo "WARNING: question 3 no longer requires the candidate to notice that."
    fi

    # Warm the image on every node, in the background: the question is about the
    # Metrics API, not about waiting for a pull.
    IMAGE=$(grep -oE 'image:[[:space:]]*[^[:space:]]*metrics-server[^[:space:]]*' "$MANIFEST" \
        | head -1 | awk '{print $2}')
    if [ -n "$IMAGE" ] && [ ! -f /tmp/exam/node-ssh-unavailable ]; then
        echo "pre-pulling ${IMAGE} on the nodes"
        while IFS='=' read -r alias name; do
            [ -n "$alias" ] || continue
            ssh -o ConnectTimeout=10 -o BatchMode=yes "$alias" \
                "setsid nohup crictl pull ${IMAGE} >/dev/null 2>&1 &" >/dev/null 2>&1 || true
        done < /tmp/exam/nodes.env
    fi
fi

echo "Setup completed for Question 3"
