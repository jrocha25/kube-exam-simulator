#!/bin/bash
set -e

# Shared preamble. Setup scripts are picked up by the plain glob "q*_setup.sh" in
# jumphost/scripts/prepare-exam-env.sh, so this file runs first (glob order is
# q0, q1, q10..q18, q2..q9) even though no question maps to it.
#
# This lab runs on the kubeadm cluster flavour ("clusterType": "kind" in
# config.json). Three capabilities that a k3s lab simply does not have are
# load-bearing here, and all three are probed once, up front, rather than by each
# question that depends on them:
#
#   * a shell on the nodes -- q1, q2, q4, q5 and q6 edit files on a node
#   * NetworkPolicy enforcement -- q9 and q10 are graded by live traffic
#   * the auxiliary cluster -- q8 breaks DNS cluster-wide, which is not something
#     a lab can contain, so it is staged over there instead
#
# env-setup-kind already leaves markers on the shared kubeconfig volume when any of
# them failed to come up. Re-probe here anyway: the markers say what the cluster
# build believed, this says what is true now.

mkdir -p /tmp/exam
rm -f /tmp/exam/node-ssh-unavailable /tmp/exam/networkpolicy-unavailable \
      /tmp/exam/aux-cluster-unavailable

# ---------------------------------------------------------------------------
# Node aliases. kind names its nodes cluster-control-plane / cluster-worker /
# cluster-worker2, but every question speaks in CKA terms (controlplane, node01,
# node02). env-setup-kind labels each node with its alias; resolve them once and
# leave the mapping on disk so no other script has to repeat the lookup.
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
# Node SSH. Bounded: a cluster without it has to say so in seconds, not stall
# the whole warm-up.
# ---------------------------------------------------------------------------
SSH_OK=yes
for target in controlplane node01; do
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
    echo "WARNING: questions 1, 2, 4, 5 and 6 will not work until then."
fi

# ---------------------------------------------------------------------------
# NetworkPolicy enforcement. The presence of a CNI that *accepts* a policy proves
# nothing -- kindnet accepts every NetworkPolicy and enforces none -- so look for
# the controller that actually does the work.
# ---------------------------------------------------------------------------
if ! kubectl get daemonset calico-node -n kube-system >/dev/null 2>&1; then
    echo "unavailable" > /tmp/exam/networkpolicy-unavailable
    echo "WARNING: Calico is not installed, so NetworkPolicy is not enforced."
    echo "WARNING: questions 9 and 10 would pass no matter what you wrote."
    echo "WARNING: rebuild the cluster image with:  ./start.sh --rebuild"
fi

# ---------------------------------------------------------------------------
# The auxiliary cluster. Question 8 stages its fault there and the candidate
# reaches it with "ssh aux", so both halves have to work: an API server the setup
# and validation scripts can drive from here, and a shell on the node.
#
# prepare-exam-env has already waited for it, so this is a check rather than a
# wait. Both probes are bounded for the same reason the node-SSH probe above is.
# ---------------------------------------------------------------------------
AUX_KUBECONFIG=/home/candidate/.kube/kubeconfig-aux
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
    echo "WARNING: question 8 will not work until then; the rest of the lab is"
    echo "WARNING: unaffected, which is the whole point of staging it over there."
fi

echo "Shared setup completed"
