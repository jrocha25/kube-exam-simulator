#!/bin/bash
set -e

# Question 2: a Pod that will not stay deleted.
#
# The fixture is a static Pod manifest planted on node01, so "kubectl delete pod"
# removes the mirror Pod and the kubelet recreates it within seconds. The only
# fix is to remove the manifest from the node, which is the half of static Pods
# that no other lab grades.
#
# It is planted on node01 rather than the control plane for two reasons: the
# candidate must not be tempted to delete anything out of
# /etc/kubernetes/manifests on the control plane, and q1 owns node02.

NAMESPACE="node-relay"
POD_BASE="relay-shim"
TARGET="node01"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

if [ -f /tmp/exam/node-ssh-unavailable ]; then
    echo "WARNING: there is no shell on the nodes, skipping setup for question 2"
    exit 0
fi

DIR=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "$TARGET" \
    "awk '/^staticPodPath:/ {print \$2}' /var/lib/kubelet/config.yaml" 2>/dev/null | tr -d '\r')
[ -n "$DIR" ] || DIR=/etc/kubernetes/manifests

# Re-plant it on every warm-up: a candidate who solved this last time has to
# solve it again.
ssh -o ConnectTimeout=10 -o BatchMode=yes "$TARGET" "cat > ${DIR}/${POD_BASE}.yaml" <<YAML || \
    echo "WARNING: could not plant the static Pod manifest on ${TARGET}"
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_BASE}
  namespace: ${NAMESPACE}
  labels:
    app: relay-shim
spec:
  containers:
  - name: shim
    image: nginx:1.27.4
YAML

# The kubelet rescans the directory every few seconds; wait, bounded, so that the
# candidate does not open the question before the symptom exists.
for _ in $(seq 1 12); do
    COUNT=$(kubectl get pods -n "$NAMESPACE" --no-headers 2>/dev/null | grep -c . || true)
    [ "${COUNT:-0}" -ge 1 ] && break
    sleep 5
done
if [ "${COUNT:-0}" -lt 1 ] ; then
    echo "WARNING: the planted static Pod has not appeared in ${NAMESPACE} yet"
fi

echo "Setup completed for Question 2"
