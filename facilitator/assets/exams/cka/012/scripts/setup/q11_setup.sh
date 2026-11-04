#!/bin/bash
set -e

# Question 11: Pending, because no node carries the label the Pod asks for.
#
# The Pod is bare -- no controller -- which is what makes "do not delete and
# recreate it" a real constraint: there is nothing to recreate it for you. Its
# UID is recorded here and checked at validation time, so the forbidden fix
# cannot collect the marks.
#
# It targets node02, not node01. A plausible wrong answer to question 2 is to
# stop node01's kubelet, and five minutes later the node controller would evict
# this Pod with nothing to bring it back -- costing the candidate a question they
# had nothing to do with.
#
# busybox rather than nginx so that the image is already on every node and a
# correct answer is never waiting on a cold pull inside the validation window.

NAMESPACE="sched-epicenter"
POD="epicenter-plot"
DIR="/tmp/exam/q11"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# A node labelled by a previous attempt would make this Pod schedule immediately.
kubectl label nodes --all seismo.io/duty- >/dev/null 2>&1 || true

kubectl delete pod "$POD" -n "$NAMESPACE" --ignore-not-found=true --timeout=60s >/dev/null 2>&1 || true

kubectl apply -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: epicenter-plot
  namespace: sched-epicenter
  labels:
    app: epicenter-plot
spec:
  nodeSelector:
    seismo.io/duty: plotting
  containers:
  - name: plot
    image: busybox:1.36
    command: ["sh", "-c", "while true; do echo plotting epicentres; sleep 30; done"]
YAML

mkdir -p "$DIR"
rm -f "${DIR}/pod.uid" "${DIR}/pod.sha"
# Recorded on every warm-up: the identity the candidate has to preserve is this
# attempt's, not a previous one's. The spec is fingerprinted as well, because
# editing the Pod is forbidden too and a recreated Pod with the same selector
# would otherwise look untouched.
kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.metadata.uid}' 2>/dev/null > "${DIR}/pod.uid" || true
# nodeName is excluded: the scheduler writes it, so a fingerprint taken while the
# Pod is Pending would never match once the Pod is Running.
kubectl get pod "$POD" -n "$NAMESPACE" -o json 2>/dev/null \
    | jq -S '.spec | del(.nodeName)' | sha256sum | awk '{print $1}' > "${DIR}/pod.sha" || true

if [ ! -s "${DIR}/pod.uid" ]; then
    echo "WARNING: could not record the UID of ${POD}; step 1 of question 11 will fail"
fi

echo "Setup completed for Question 11"
