#!/bin/bash
set -e

# Shared preamble. Setup scripts are picked up by the plain glob "q*_setup.sh" in
# jumphost/scripts/prepare-exam-env.sh, so this file runs first (glob order is
# q0, q1, q10..q17, q2..q9) even though no question maps to it.
#
# This lab runs on the kubeadm cluster flavour ("clusterType": "kind") with an
# auxiliary cluster ("auxCluster": "kind"). Three capabilities are load-bearing
# and all three are probed once, up front, rather than by each question:
#
#   * a shell on the nodes -- q13, q14 and q17 work on a node
#   * NetworkPolicy enforcement -- q4 and q5 are graded entirely by live traffic,
#     and a CNI that accepts every policy and enforces none would pass every
#     "can reach" check and fail every "cannot reach" one, silently
#   * the auxiliary cluster -- q6 rewrites the CoreDNS Corefile, which is a
#     cluster-wide change no lab can contain on the cluster its other sixteen
#     questions run on

AUX_KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

mkdir -p /tmp/exam
rm -f /tmp/exam/node-ssh-unavailable /tmp/exam/networkpolicy-unavailable \
      /tmp/exam/aux-cluster-unavailable

# ---------------------------------------------------------------------------
# Node aliases. kind names its nodes cluster-control-plane / cluster-worker /
# cluster-worker2, but every question speaks in CKA terms. env-setup-kind labels
# each node with its alias; resolve them once and leave the mapping on disk so
# no script ever hardcodes "cluster-worker2".
# ---------------------------------------------------------------------------
: > /tmp/exam/nodes.env
for alias in controlplane node01 node02; do
    name=$(kubectl get nodes -l "ck-x.io/alias=${alias}" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -n "$name" ]; then
        echo "${alias}=${name}" >> /tmp/exam/nodes.env
    else
        echo "WARNING: no node carries the label ck-x.io/alias=${alias}"
    fi
done
echo "Node aliases:"
cat /tmp/exam/nodes.env

# ---------------------------------------------------------------------------
# Node SSH. Bounded: a cluster without it has to say so in seconds, not stall
# the whole warm-up.
# ---------------------------------------------------------------------------
SSH_OK=yes
for target in controlplane node01 node02; do
    if ! ssh -o ConnectTimeout=10 -o BatchMode=yes "$target" true >/dev/null 2>&1; then
        SSH_OK=no
        echo "WARNING: cannot ssh to ${target}"
    fi
done

if [ "$SSH_OK" != yes ]; then
    echo "unavailable" > /tmp/exam/node-ssh-unavailable
    echo "WARNING: there is no shell on the cluster nodes."
    echo "WARNING: this lab needs the kubeadm cluster flavour. Check that"
    echo "WARNING: config.json carries \"clusterType\": \"kind\" and rebuild with:"
    echo "WARNING:   ./start.sh --stop && ./start.sh --rebuild"
    echo "WARNING: questions 13, 14 and 17 will not work until then."
fi

# ---------------------------------------------------------------------------
# NetworkPolicy enforcement. Questions 4 and 5 are graded by opening TCP
# connections, so an unenforced cluster does not make them fail -- it makes them
# score wrong. Look for Calico (kindnet, which kind ships by default, accepts
# every policy and enforces none), then prove enforcement functionally in a
# scratch namespace the way cka/008 does.
# ---------------------------------------------------------------------------
NP_OK=yes
if ! kubectl get daemonset calico-node -n kube-system >/dev/null 2>&1; then
    NP_OK=no
    echo "WARNING: Calico is not installed; NetworkPolicies will not be enforced"
else
    PROBE_NS="np-enforcement-probe"
    kubectl delete namespace "$PROBE_NS" --ignore-not-found=true --wait=true >/dev/null 2>&1 || true
    kubectl create namespace "$PROBE_NS" >/dev/null 2>&1 || true
    kubectl apply -f - >/dev/null 2>&1 <<PROBE || true
apiVersion: v1
kind: Pod
metadata:
  name: server
  namespace: $PROBE_NS
  labels:
    role: server
spec:
  containers:
  - name: server
    image: nginx:1.27.4
---
apiVersion: v1
kind: Pod
metadata:
  name: client
  namespace: $PROBE_NS
  labels:
    role: client
spec:
  containers:
  - name: client
    image: nginx:1.27.4
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: $PROBE_NS
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
PROBE
    kubectl wait --for=condition=Ready pod/server pod/client -n "$PROBE_NS" --timeout=120s >/dev/null 2>&1 \
        || echo "WARNING: the enforcement probe Pods did not become ready"
    SERVER_IP=$(kubectl get pod server -n "$PROBE_NS" -o jsonpath='{.status.podIP}' 2>/dev/null || true)
    if [ -n "$SERVER_IP" ]; then
        # A deny-all namespace must cut this off. If it does not, nothing is enforcing.
        if kubectl exec -n "$PROBE_NS" client -- timeout 4 bash -c "echo > /dev/tcp/${SERVER_IP}/80" >/dev/null 2>&1; then
            NP_OK=no
            echo "WARNING: a deny-all NetworkPolicy did not stop traffic"
        fi
    else
        NP_OK=no
        echo "WARNING: could not run the NetworkPolicy enforcement probe"
    fi
    kubectl delete namespace "$PROBE_NS" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true
fi

if [ "$NP_OK" != yes ]; then
    echo "unavailable" > /tmp/exam/networkpolicy-unavailable
    echo "WARNING: NetworkPolicies are not enforced on this cluster."
    echo "WARNING: rebuild the cluster image with:  ./start.sh --rebuild"
    echo "WARNING: questions 4 and 5 cannot be graded honestly until then."
fi

# ---------------------------------------------------------------------------
# The auxiliary cluster. Question 6 is staged there and the candidate reaches it
# with "ssh aux", so both halves have to work: an API server the setup and
# validation scripts can drive from here, and a shell on the node.
#
# prepare-exam-env has already waited for it, so this is a check rather than a
# wait, and bounded for the same reason the node-SSH probe above is.
# ---------------------------------------------------------------------------
AUX_OK=yes
if ! kubectl --kubeconfig="$AUX_KUBECONFIG" --request-timeout=20s get nodes >/dev/null 2>&1; then
    AUX_OK=no
    echo "WARNING: cannot reach the auxiliary cluster's API server"
elif ! ssh -o ConnectTimeout=10 -o BatchMode=yes aux true >/dev/null 2>&1; then
    AUX_OK=no
    echo "WARNING: cannot ssh to the auxiliary cluster node"
fi

if [ "$AUX_OK" != yes ]; then
    echo "unavailable" > /tmp/exam/aux-cluster-unavailable
    echo "WARNING: there is no auxiliary cluster."
    echo "WARNING: this lab needs \"auxCluster\": \"kind\" in config.json, and both"
    echo "WARNING: the jumphost and cluster images built from local source:"
    echo "WARNING:   ./start.sh --stop && ./start.sh --rebuild"
    echo "WARNING: question 6 will not work until then; the rest of the lab is"
    echo "WARNING: unaffected, which is the whole point of staging it there."
fi

echo "Shared setup completed"
