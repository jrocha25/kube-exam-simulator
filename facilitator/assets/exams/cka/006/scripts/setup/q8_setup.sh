#!/bin/bash
set -e

# Question 8: a cluster-wide DNS outage, staged on the auxiliary cluster.
#
# The fault is the same one a real cluster hits after a botched CoreDNS upgrade:
# the kube-dns Service keeps selecting a label the CoreDNS pods no longer carry, so
# it has zero endpoints and every lookup in the cluster times out. The CoreDNS pods
# themselves stay perfectly healthy, which is what makes it worth diagnosing --
# "kubectl get pods -n kube-system" shows nothing wrong.
#
# It runs against the auxiliary cluster (config.json: "auxCluster": "kind"), not the
# lab's own. Taking name resolution down cluster-wide is not something a lab can
# contain: it used to live in a file named qz_setup.sh purely so that it would sort
# after every other setup script, and every question that came after it still had to
# be written around a cluster that could not resolve a name -- including question 7,
# whose stated acceptance criterion was a lookup that could not succeed until this
# question was solved. On its own cluster the blast radius is exactly this question.

AUX_KUBECONFIG=/home/candidate/.kube/kubeconfig-aux
NAMESPACE="dns-check"

if [ -f /tmp/exam/aux-cluster-unavailable ]; then
    echo "WARNING: the auxiliary cluster is unavailable, skipping question 8 setup."
    echo "WARNING: see the warning from q0_setup.sh for the fix."
    exit 0
fi

export KUBECONFIG="$AUX_KUBECONFIG"

# ---------------------------------------------------------------------------
# The Pod the candidate probes DNS from.
#
# No nodeSelector: the auxiliary cluster is a single control-plane node, and none
# of the node-level questions that constrain placement on the primary cluster
# (question 2's reduced Allocatable, question 5's drain) exist over here.
# ---------------------------------------------------------------------------
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete pod --all -n "$NAMESPACE" --ignore-not-found=true --wait=false

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: ticker
  namespace: $NAMESPACE
  labels:
    app: ticker
spec:
  containers:
  - name: client
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
YAML

kubectl wait --for=condition=Ready pod/ticker -n "$NAMESPACE" --timeout=180s \
    || echo "WARNING: the ticker pod did not become ready"

# ---------------------------------------------------------------------------
# The fault. Planted after the probe Pod is up, so the image pull and the
# scheduling that precede it still happen on a cluster that can resolve names.
# ---------------------------------------------------------------------------
REAL_SELECTOR="kube-dns"
BROKEN_SELECTOR="core-dns"

CURRENT=$(kubectl get service kube-dns -n kube-system \
    -o jsonpath='{.spec.selector.k8s-app}' 2>/dev/null || true)

if [ -z "$CURRENT" ]; then
    echo "WARNING: the kube-dns Service has no k8s-app selector to break."
    echo "WARNING: question 8 will not have a fault to find."
    exit 0
fi

if [ "$CURRENT" != "$REAL_SELECTOR" ]; then
    echo "WARNING: kube-dns already selects '${CURRENT}', not '${REAL_SELECTOR}'."
fi

kubectl patch service kube-dns -n kube-system \
    -p "{\"spec\":{\"selector\":{\"k8s-app\":\"${BROKEN_SELECTOR}\"}}}"

# Confirm the outage is real: a selector change that still matched something would
# leave a question with no symptom.
for attempt in $(seq 1 12); do
    COUNT=$(kubectl get endpointslice -n kube-system \
        -l kubernetes.io/service-name=kube-dns \
        -o jsonpath='{.items[*].endpoints[*].addresses[0]}' 2>/dev/null | wc -w)
    [ "$COUNT" -eq 0 ] && break
    sleep 5
done

if [ "${COUNT:-1}" -ne 0 ]; then
    echo "WARNING: kube-dns still has endpoints after the selector was broken."
fi

# The captured output lands on the jumphost, not on either cluster.
rm -rf /tmp/exam/q8
mkdir -p /tmp/exam/q8

echo "Setup completed for Question 8 (auxiliary cluster DNS is now broken, by design)"
