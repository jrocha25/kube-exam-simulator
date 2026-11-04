#!/bin/bash
set -e

# Question 17: read a value out of a running container that has no shell. The
# image is the pause image already on every node (no pull), which runs as uid
# 65535 and ships nothing but /pause. An ephemeral container with --target
# shares its process namespace, but reading /proc/1/environ of another user's
# process needs CAP_SYS_PTRACE: kubectl debug's default (legacy) profile is
# refused, "--profile=general" adds the capability and works. Checked on
# kubectl v1.34.10 against kindest/node v1.34.8.
#
# Only a checksum of the token is kept on the jumphost, and the Secret is
# deleted once the Pod is running, so the Pod's environment really is the only
# copy. crictl inspect on node01 would also show it, which is why the
# validation requires the ephemeral container and the question forbids the node.

NAMESPACE="ts-lighthouse"
POD="beacon-core"
STATE_DIR=/tmp/exam/q17

mkdir -p "$STATE_DIR"
rm -f "$STATE_DIR/token.txt"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found=true --wait=true

PAUSE_IMAGE=$(ssh -n -o ConnectTimeout=10 -o BatchMode=yes node01 \
    "crictl images | awk '\$1 == \"registry.k8s.io/pause\" {print \$1 \":\" \$2; exit}'" 2>/dev/null || true)
PAUSE_IMAGE=${PAUSE_IMAGE:-registry.k8s.io/pause:3.10}

TOKEN="lh-$(head -c 18 /dev/urandom | od -An -tx1 | tr -d ' \n')"
kubectl create secret generic beacon-key -n "$NAMESPACE" --from-literal=token="$TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $POD
  namespace: $NAMESPACE
  labels:
    app: beacon
spec:
  nodeSelector:
    ck-x.io/alias: node01
  containers:
  - name: core
    image: $PAUSE_IMAGE
    imagePullPolicy: IfNotPresent
    env:
    - name: LIGHT_TOKEN
      valueFrom:
        secretKeyRef:
          name: beacon-key
          key: token
YAML

kubectl wait --for=condition=Ready pod/"$POD" -n "$NAMESPACE" --timeout=90s >/dev/null \
    || echo "WARNING: $POD did not become ready"

printf '%s' "$TOKEN" | sha256sum | awk '{print $1}' > "$STATE_DIR/.token.sha256"
kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.metadata.uid}' > "$STATE_DIR/.pod.uid"
kubectl delete secret beacon-key -n "$NAMESPACE"

echo "Setup completed for Question 17"
