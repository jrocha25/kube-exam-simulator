#!/bin/bash
set -e

# Shared preamble. Setup scripts are picked up by the plain glob "q*_setup.sh" in
# jumphost/scripts/prepare-exam-env.sh, so this file runs first (glob order is
# q0, q1, q10..q13, q2..q9) even though no question maps to it.
#
# This lab runs on the kubeadm cluster flavour ("clusterType": "kind") with three
# workers and no auxiliary cluster. Three capabilities are load-bearing and all
# three are probed once, up front, rather than by each question:
#
#   * a shell on the nodes -- q1 and q2 are about what the kubelet reads off disk
#   * three distinct workers -- q1 stages on node02, q2 on node01, q11 labels
#     node01 and q12 taints node03, so each node-touching question owns one
#   * NetworkPolicy enforcement -- q3 and q4 are graded entirely by live traffic,
#     and a CNI that accepts every policy and enforces none would pass every
#     "can reach" check and fail every "cannot reach" one, silently

ALIASES="controlplane node01 node02 node03"

mkdir -p /tmp/exam
rm -f /tmp/exam/node-ssh-unavailable /tmp/exam/networkpolicy-unavailable \
      /tmp/exam/insufficient-nodes

# ---------------------------------------------------------------------------
# Node aliases. kind names its nodes cluster-control-plane / cluster-worker /
# cluster-worker2, but every question speaks in CKA terms. env-setup-kind labels
# each node with its alias; resolve them once and leave the mapping on disk so
# no script ever hardcodes "cluster-worker2".
# ---------------------------------------------------------------------------
: > /tmp/exam/nodes.env
MISSING=no
for alias in $ALIASES; do
    name=$(kubectl get nodes -l "ck-x.io/alias=${alias}" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
    if [ -n "$name" ]; then
        echo "${alias}=${name}" >> /tmp/exam/nodes.env
    else
        MISSING=yes
        echo "WARNING: no node carries the label ck-x.io/alias=${alias}"
    fi
done
echo "Node aliases:"
cat /tmp/exam/nodes.env

if [ "$MISSING" != no ]; then
    echo "unavailable" > /tmp/exam/insufficient-nodes
    echo "WARNING: this lab needs a control plane and three workers."
    echo "WARNING: check that config.json carries \"workerNodes\": 3 and rebuild with:"
    echo "WARNING:   ./start.sh --stop && ./start.sh --rebuild"
    echo "WARNING: questions 1, 2, 11 and 12 each need a node of their own."
fi

# ---------------------------------------------------------------------------
# Node SSH. Bounded: a cluster without it has to say so in seconds, not stall
# the whole warm-up.
# ---------------------------------------------------------------------------
SSH_OK=yes
for target in $ALIASES; do
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
    echo "WARNING: questions 1 and 2 will not work until then."
fi

# ---------------------------------------------------------------------------
# NetworkPolicy enforcement. Questions 3 and 4 are graded by opening TCP
# connections, so an unenforced cluster does not make them fail -- it makes them
# score wrong. Look for Calico (kindnet, which kind ships by default, accepts
# every policy and enforces none), then prove enforcement functionally in a
# scratch namespace the way cka/008 and cka/011 do.
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
    echo "WARNING: questions 3 and 4 cannot be graded honestly until then."
fi

echo "Shared setup completed"
