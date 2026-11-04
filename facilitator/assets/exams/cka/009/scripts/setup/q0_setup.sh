#!/bin/bash

set -e

# Shared preamble. Setup scripts are picked up by the plain glob "q*_setup.sh" in
# jumphost/scripts/prepare-exam-env.sh, so this file runs first (glob order is
# q0, q1, q10..q12, q2..q9) even though no question maps to it.
#
# This lab grades pod placement, which needs a node topology that k3d does not
# provide. The kind flavour labels its nodes "ck-x.io/alias=..." in env-setup-kind,
# but the k3d path labels nothing at all, and no k3s node carries a zone label. So
# the topology every scheduling question reasons about is built here.
#
# The node layout, and why it is this shape:
#
#   k3d-cluster-server-0   node00   zone edge-1   node-class general
#   k3d-cluster-agent-0    node01   zone edge-1   node-class compute
#   k3d-cluster-agent-1    node02   zone edge-2   node-class memory   decommission=pending
#
#   - Two zones holding 2 and 1 nodes, not 1 and 1. An even split is satisfied
#     identically by a zone spread and a hostname spread, so it would not
#     distinguish a correct answer to q10 from a lucky one.
#   - The decommission label gives q6 a second, negative expression to write, and
#     narrows its eligible set to exactly one node so placement is unambiguous.
#
# The k3d server node is schedulable -- k3s runs workloads on the server unless
# --disable-agent is passed, and env-setup does not pass it -- so this is a
# three-node cluster for scheduling purposes, not a two-node one. Several
# questions depend on that, hence the probe at the end.

mkdir -p /tmp/exam

# ---------------------------------------------------------------------------
#   Node discovery
# ---------------------------------------------------------------------------
# Resolve by role rather than by name. The names are predictable on k3d, but a
# lab that hardcodes them fails silently and confusingly if the flavour changes.

SERVER=$(kubectl get nodes -l node-role.kubernetes.io/control-plane \
    -o jsonpath='{.items[0].metadata.name}' 2> /dev/null || true)

# Sorted so agent-0 and agent-1 keep their aliases across attempts.
AGENTS=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2> /dev/null | sort || true)

AGENT0=$(echo "$AGENTS" | sed -n '1p')
AGENT1=$(echo "$AGENTS" | sed -n '2p')

if [[ -z "$SERVER" || -z "$AGENT0" || -z "$AGENT1" ]]; then
    echo "WARNING: expected one control-plane node and two agents, found:"
    echo "WARNING:   control-plane: '${SERVER:-none}'"
    echo "WARNING:   agents: $(echo "$AGENTS" | tr '\n' ' ')"
    echo "WARNING: this lab needs three schedulable nodes; check workerNodes in config.json"
fi

label_node() {
    local NODE="$1"
    shift
    [[ -z "$NODE" ]] && return 0
    kubectl label node "$NODE" "$@" --overwrite > /dev/null 2>&1 \
        || echo "WARNING: could not label node ${NODE}"
}

label_node "$SERVER" "ck-x.io/alias=node00" "topology.kubernetes.io/zone=edge-1" "node-class=general"
label_node "$AGENT0" "ck-x.io/alias=node01" "topology.kubernetes.io/zone=edge-1" "node-class=compute"
label_node "$AGENT1" "ck-x.io/alias=node02" "topology.kubernetes.io/zone=edge-2" "node-class=memory" "decommission=pending"

# The server must not keep a stale decommission label from an earlier attempt --
# q6's eligible set is defined by its absence.
for NODE in "$SERVER" "$AGENT0"; do
    [[ -n "$NODE" ]] && kubectl label node "$NODE" "decommission-" > /dev/null 2>&1 || true
done

# ---------------------------------------------------------------------------
#   Flavour guard
# ---------------------------------------------------------------------------
# An outdated jumphost image predates clusterType forwarding and would bring
# this lab up on some other flavour entirely.

if [[ -n "$SERVER" && "$SERVER" != k3d-* ]]; then
    echo "WARNING: node names do not look like k3d ('$SERVER')."
    echo "WARNING: this lab is written for \"clusterType\": \"k3d\"; rebuild with:"
    echo "WARNING:   ./start.sh --stop && ./start.sh --rebuild"
fi

# ---------------------------------------------------------------------------
#   Schedulable-node probe
# ---------------------------------------------------------------------------
# q8, q10 and q12 are graded on pods landing on distinct nodes, and q10 needs two
# zones. All of that assumes three schedulable nodes. If a future k3s release
# taints the server, those questions become ungradeable -- and an ungradeable
# check that simply fails looks to the candidate like a wrong answer. Write a
# marker so they can fail loudly, naming the real cause.

SCHEDULABLE=$(kubectl get nodes -o json 2> /dev/null | jq '
    [ .items[]
      | select((.spec.unschedulable // false) == false)
      | select([.spec.taints[]? | select(.effect == "NoSchedule" or .effect == "NoExecute")] | length == 0)
      | select([.status.conditions[]? | select(.type == "Ready" and .status == "True")] | length > 0)
    ] | length' 2> /dev/null || echo 0)

if [[ "$SCHEDULABLE" -lt 3 ]]; then
    echo "insufficient" > /tmp/exam/insufficient-nodes
    echo "WARNING: only ${SCHEDULABLE} schedulable node(s) found; this lab needs 3."
    echo "WARNING: questions 8, 10 and 12 are graded on pods landing on distinct nodes."
    echo "WARNING: the k3d server node is normally schedulable -- check for a NoSchedule taint on it."
else
    rm -f /tmp/exam/insufficient-nodes
fi

echo "Shared setup completed (schedulable nodes: ${SCHEDULABLE})"
