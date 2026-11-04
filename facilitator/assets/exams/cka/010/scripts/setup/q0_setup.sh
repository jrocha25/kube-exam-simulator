#!/bin/bash
set -e

# Shared preamble. Setup scripts are picked up by the plain glob "q*_setup.sh" in
# jumphost/scripts/prepare-exam-env.sh, so this file runs first (glob order is
# q0, q1, q10..q16, q2..q9, qz) even though no question maps to it.
#
# This lab runs on the kubeadm cluster flavour ("clusterType": "kind") with an
# auxiliary cluster that is deliberately one Kubernetes minor behind
# ("auxNodeImage" in config.json). Four capabilities are load-bearing and all
# four are probed once, up front, rather than by each question:
#
#   * a shell on the nodes -- q2, q4, q5 and q6 work on a node
#   * NetworkPolicy/CNI -- q2 grades the network add-on re-adopting a node
#   * the auxiliary cluster -- q1 upgrades it and q3 restores its etcd, both
#     of which take its API server down, which is not something a lab can
#     contain on the cluster every other question runs on
#   * the auxiliary cluster being on the OLD minor -- otherwise q1 has nothing
#     to upgrade, and q1's setup would be downgrading binaries under a running
#     kubelet
#
# env-setup-kind leaves markers on the shared kubeconfig volume when any of the
# first three failed to come up. Re-probe here anyway: the markers say what the
# cluster build believed, this says what is true now.

AUX_KUBECONFIG=/home/candidate/.kube/kubeconfig-aux
EXPECTED_AUX_MINOR="v1.33."

mkdir -p /tmp/exam
rm -f /tmp/exam/node-ssh-unavailable /tmp/exam/networkpolicy-unavailable \
      /tmp/exam/aux-cluster-unavailable /tmp/exam/aux-version-unexpected

# ---------------------------------------------------------------------------
# Node aliases. kind names its nodes cluster-control-plane / cluster-worker /
# cluster-worker2 / cluster-worker3, but every question speaks in CKA terms.
# env-setup-kind labels each node with its alias; resolve them once and leave the
# mapping on disk. This has to happen before q2_setup.sh removes node03 from the
# cluster -- once the Node object is gone, so is its label, and q2's validation
# scripts find the node's name in this file.
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
# Keep every other question's fixtures off node02 and node03. Setup scripts run
# in glob order (q1, q10..q16, q2..q9), so most fixtures are created *before*
# q2_setup.sh removes node03 from the cluster and q5_setup.sh takes node02's
# kubelet down -- and a bare Pod (q13's resolver, q7's canary) that had landed
# on either would be deleted with the node and never come back. Cordon both
# here, before anything is scheduled. q5 uncordons node02 right before it
# stages its own Deployment there; node03 comes back as a fresh, schedulable
# Node object when the candidate rejoins it.
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
    echo "WARNING: questions 2, 4, 5 and 6 will not work until then."
fi

# ---------------------------------------------------------------------------
# The CNI. kindnet accepts every NetworkPolicy and enforces none, and would also
# not be what the candidate sees re-adopt node03 in question 2, so look for the
# controller that actually does the work.
# ---------------------------------------------------------------------------
if ! kubectl get daemonset calico-node -n kube-system >/dev/null 2>&1; then
    echo "unavailable" > /tmp/exam/networkpolicy-unavailable
    echo "WARNING: Calico is not installed."
    echo "WARNING: rebuild the cluster image with:  ./start.sh --rebuild"
fi

# ---------------------------------------------------------------------------
# The auxiliary cluster. Questions 1 and 3 are staged there and the candidate
# reaches it with "ssh aux", so both halves have to work: an API server the
# setup and validation scripts can drive from here, and a shell on the node.
#
# prepare-exam-env has already waited for it, so this is a check rather than a
# wait. Both probes are bounded for the same reason the node-SSH probe above is.
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
    echo "WARNING: questions 1 and 3 will not work until then; the rest of the lab"
    echo "WARNING: is unaffected, which is the whole point of staging them there."
else
    # The version the aux cluster came up on. Question 1 needs it to be the minor
    # *behind* the lab cluster's; if it is not, config.json's auxNodeImage was not
    # honoured -- almost always a jumphost or facilitator image that predates the
    # option and silently dropped the argument.
    AUX_VERSION=$(kubectl --kubeconfig="$AUX_KUBECONFIG" get nodes \
        -o jsonpath='{.items[0].status.nodeInfo.kubeletVersion}' 2>/dev/null || true)
    echo "Auxiliary cluster is running ${AUX_VERSION:-unknown}"
    echo "${AUX_VERSION}" > /tmp/exam/aux-version
    case "$AUX_VERSION" in
        ${EXPECTED_AUX_MINOR}*) ;;
        *)
            echo "unexpected" > /tmp/exam/aux-version-unexpected
            echo "WARNING: the auxiliary cluster is on ${AUX_VERSION:-unknown}, not ${EXPECTED_AUX_MINOR}x."
            echo "WARNING: config.json's auxNodeImage was not applied. Rebuild the jumphost,"
            echo "WARNING: cluster and facilitator images from local source:"
            echo "WARNING:   ./start.sh --stop && ./start.sh --rebuild"
            echo "WARNING: question 1 has nothing to upgrade and will be skipped."
            ;;
    esac
fi

echo "Shared setup completed"
