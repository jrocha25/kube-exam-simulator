#!/bin/bash
set -e

# Shared preamble. Setup scripts are picked up by the plain glob "q*_setup.sh" in
# jumphost/scripts/prepare-exam-env.sh, so this file runs first (glob order is
# q0, q1, q10..q16, q2..q9) even though no question maps to it.
#
# This lab runs on the kubeadm cluster flavour with an auxiliary cluster. Three
# capabilities are load-bearing and all three are probed once, up front:
#
#   * a shell on the nodes -- q5, q7, q9 and q12 work on a node
#   * NetworkPolicy enforcement -- q6 is graded by live traffic
#   * the auxiliary cluster -- q3 takes its API server down and q11 removes its
#     CNI, neither of which any lab can contain on the cluster everything else uses

AUX_KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

mkdir -p /tmp/exam
rm -f /tmp/exam/node-ssh-unavailable /tmp/exam/networkpolicy-unavailable \
      /tmp/exam/aux-cluster-unavailable

# ---------------------------------------------------------------------------
# Node aliases, resolved once. q9 takes node03's kubelet down, and reading names
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
# Reserve node02 and node03. q13 divides node02's allocatable between its own
# Pods, and q9 breaks node03's kubelet. Setup runs q1, q10..q16, q2..q9, so most
# fixtures are created before either; cordon both now. q13 uncordons node02
# before staging on it, q9 uncordons node03 once its fault has landed.
# ---------------------------------------------------------------------------
for alias in node02 node03; do
    name=$(grep "^${alias}=" /tmp/exam/nodes.env | cut -d= -f2)
    [ -n "$name" ] && kubectl cordon "$name" >/dev/null 2>&1 && echo "cordoned ${alias} (${name}) for the rest of setup"
done

# ---------------------------------------------------------------------------
# Node SSH. Bounded: a cluster without it has to say so in seconds.
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
    echo "WARNING: this lab needs the kubeadm cluster flavour. Rebuild with:"
    echo "WARNING:   ./start.sh --stop && ./start.sh --rebuild"
    echo "WARNING: questions 5, 7, 9 and 12 will not work until then."
fi

# ---------------------------------------------------------------------------
# The CNI. kindnet accepts every NetworkPolicy and enforces none.
# ---------------------------------------------------------------------------
if ! kubectl get daemonset calico-node -n kube-system >/dev/null 2>&1; then
    echo "unavailable" > /tmp/exam/networkpolicy-unavailable
    echo "WARNING: Calico is not installed, so question 6 cannot be graded fairly."
    echo "WARNING: rebuild the cluster image with:  ./start.sh --rebuild"
fi

# ---------------------------------------------------------------------------
# The auxiliary cluster. prepare-exam-env has already waited for it.
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
    echo "WARNING: questions 3 and 11 will not work until then; the rest of the lab is unaffected."
fi

echo "Shared setup completed"
