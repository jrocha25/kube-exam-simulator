#!/bin/bash
set -e

# A kubelet-managed Pod is not just a Pod that happens to be on the right node.
# The kubelet names the mirror Pod <name>-<nodeName>, annotates it
# kubernetes.io/config.mirror, and gives it an ownerReference to the Node. A Pod
# created through the API server has none of those, whatever it is called -- which
# is what stops "kubectl run" from scoring this question.
#
# The node is checked Ready first: a Pod on a node whose kubelet has died keeps
# reporting Running for five minutes, and question 2 invites poking at kubelets.

NAMESPACE="node-sensor"
POD_BASE="sensor-collector"
ALIAS="node02"

if [[ -f /tmp/exam/insufficient-nodes ]]; then
    echo "❌ This lab needs three worker nodes, so this question cannot be graded."
    echo "   Rebuild with: ./start.sh --stop && ./start.sh --rebuild"
    exit 1
fi

NODE=$(awk -F= -v a="$ALIAS" '$1==a {print $2}' /tmp/exam/nodes.env 2>/dev/null | head -1)
if [[ -z "$NODE" ]]; then
    NODE=$(kubectl get nodes -l "ck-x.io/alias=${ALIAS}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
fi
if [[ -z "$NODE" ]]; then
    echo "❌ No node carries the label ck-x.io/alias=${ALIAS}"
    exit 1
fi

READY=$(kubectl get node "$NODE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
if [[ "$READY" != "True" ]]; then
    echo "❌ Node '${NODE}' (${ALIAS}) is not Ready, so what runs on it cannot be judged"
    exit 1
fi

POD="${POD_BASE}-${NODE}"
JSON=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null || true)

# Fail fast: nothing is converging at the end of an exam, so an absent object is
# an answer, not something to wait 60 seconds for.
if [[ -z "$JSON" ]]; then
    echo "❌ No mirror Pod '${POD}' in namespace '${NAMESPACE}'"
    echo "   The kubelet names a static Pod's mirror <name>-<nodeName>; a Pod created through"
    echo "   the API server would be named '${POD_BASE}' and does not count."
    exit 1
fi

MIRROR=$(jq -r '.metadata.annotations["kubernetes.io/config.mirror"] // empty' <<<"$JSON")
OWNER=$(jq -r '.metadata.ownerReferences[0].kind // empty' <<<"$JSON")
if [[ -z "$MIRROR" && "$OWNER" != "Node" ]]; then
    echo "❌ '${POD}' was not created by a kubelet from a manifest on disk"
    echo "   A mirror Pod carries the kubernetes.io/config.mirror annotation and is owned by the Node."
    exit 1
fi

ON=$(jq -r '.spec.nodeName // empty' <<<"$JSON")
if [[ "$ON" != "$NODE" ]]; then
    echo "❌ '${POD}' runs on '${ON:-nowhere}', not on '${NODE}' (${ALIAS})"
    exit 1
fi

# Present but not yet Running is the one thing worth a bounded wait.
PHASE=$(jq -r '.status.phase // empty' <<<"$JSON")
if [[ "$PHASE" != "Running" ]]; then
    for _ in $(seq 1 6); do
        sleep 5
        PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || true)
        [[ "$PHASE" == "Running" ]] && break
    done
fi
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ '${POD}' is ${PHASE:-absent}, expected Running"
    exit 1
fi

echo "✅ Mirror Pod '${POD}' is Running on ${ALIAS}, managed by that node's kubelet"
exit 0
