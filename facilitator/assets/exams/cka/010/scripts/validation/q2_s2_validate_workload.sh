#!/bin/bash
set -e

# node03's ck-x.io/alias label went with its Node object when setup removed it
# from the cluster, so its kind name is read from the map q0_setup.sh wrote
# beforehand rather than resolved through the label.
NODE=$(grep "^node03=" /tmp/exam/nodes.env 2>/dev/null | cut -d= -f2 || true)
NODE=${NODE:-cluster-worker3}

NAMESPACE="join-node"
PROBE="join-probe-$$"

if ! kubectl get node "$NODE" >/dev/null 2>&1; then
    echo "❌ Node '$NODE' is not part of the cluster"
    exit 1
fi

# The network add-on has to be running on the node before any Pod there can
# get an address. Calico is a DaemonSet, so re-joining is enough -- if the
# node really joined.
CALICO=$(kubectl get pods -n kube-system -l k8s-app=calico-node \
    --field-selector "spec.nodeName=${NODE}" -o jsonpath='{.items[0].status.phase}' 2>/dev/null || true)
if [[ "$CALICO" != "Running" ]]; then
    echo "❌ No Running calico-node Pod on '$NODE' (found: ${CALICO:-none})"
    exit 1
fi

# And the proof that matters: a Pod pinned to the node comes up.
kubectl delete pod "$PROBE" -n "$NAMESPACE" --ignore-not-found=true --wait=false >/dev/null 2>&1
kubectl apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $PROBE
  namespace: $NAMESPACE
spec:
  nodeName: $NODE
  restartPolicy: Never
  containers:
  - name: probe
    image: busybox:1.36
    command: ["sh", "-c", "sleep 120"]
YAML

for _ in $(seq 1 12); do
    PHASE=$(kubectl get pod "$PROBE" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
    [[ "$PHASE" == "Running" ]] && break
    sleep 5
done
kubectl delete pod "$PROBE" -n "$NAMESPACE" --ignore-not-found=true --wait=false >/dev/null 2>&1

if [[ "$PHASE" != "Running" ]]; then
    echo "❌ A Pod scheduled on '$NODE' did not reach Running (last phase: ${PHASE:-none})"
    exit 1
fi

echo "✅ calico-node runs on '$NODE' and a Pod scheduled there started"
exit 0
