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
#   * a shell on the nodes -- q2, q4, q5, q8, q14 and q17 work on a node
#   * NetworkPolicy enforcement -- q10 is graded by live traffic, and a CNI
#     that accepts every policy and enforces none would pass every "can reach"
#     check and fail every "cannot reach" one, silently
#   * the auxiliary cluster -- q1 takes its API server and controller manager
#     down, which no lab can contain on the cluster every other question uses

AUX_KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

mkdir -p /tmp/exam
rm -f /tmp/exam/node-ssh-unavailable /tmp/exam/networkpolicy-unavailable \
      /tmp/exam/aux-cluster-unavailable

# ---------------------------------------------------------------------------
# Node aliases. kind names its nodes cluster-control-plane / cluster-worker /
# cluster-worker2 / cluster-worker3, but every question speaks in CKA terms.
# Resolve the ck-x.io/alias labels once and leave the mapping on disk. q8 takes
# node03's kubelet down, and a NotReady node is still listed, but reading names
# from this file keeps every script independent of the label surviving.
# ---------------------------------------------------------------------------
: > /tmp/exam/nodes.env
for alias in controlplane node01 node02 node03; do
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
# Reserve node02 and node03. q8 breaks node03's kubelet and q9 drains node02,
# and setup runs in glob order (q1, q10..q17, q2..q9), so most fixtures are
# created before either. A Pod of another question that landed on node03 would
# go with the kubelet; one on node02 would be in the way of the drain, and
# kubectl drain refuses a Pod with no controller. Cordon both before anything is
# scheduled. q8 and q9 uncordon their own node right before staging on it.
# ---------------------------------------------------------------------------
for alias in node02 node03; do
    name=$(grep "^${alias}=" /tmp/exam/nodes.env | cut -d= -f2)
    [ -n "$name" ] && kubectl cordon "$name" >/dev/null 2>&1 && echo "cordoned ${alias} (${name}) for the rest of setup"
done

# ---------------------------------------------------------------------------
# Node SSH. Bounded: a cluster without it has to say so in seconds, not stall
# the whole warm-up.
# ---------------------------------------------------------------------------
SSH_OK=yes
for target in controlplane node01 node02 node03; do
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
    echo "WARNING: questions 2, 4, 5, 8, 14 and 17 will not work until then."
fi

# ---------------------------------------------------------------------------
# The CNI. kindnet accepts every NetworkPolicy and enforces none.
# ---------------------------------------------------------------------------
if ! kubectl get daemonset calico-node -n kube-system >/dev/null 2>&1; then
    echo "unavailable" > /tmp/exam/networkpolicy-unavailable
    echo "WARNING: Calico is not installed, so question 10 cannot be graded fairly."
    echo "WARNING: rebuild the cluster image with:  ./start.sh --rebuild"
fi

# ---------------------------------------------------------------------------
# The auxiliary cluster. Question 1 is staged there and the candidate reaches it
# with "ssh aux", so both halves have to work. prepare-exam-env has already
# waited for it, so this is a check rather than a wait.
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
    echo "WARNING: question 1 will not work until then; the rest of the lab is unaffected."
fi

echo "Shared setup completed"
