#!/bin/bash
set -e

# The Service's cluster IP is assigned when the candidate creates it and is read
# here from the live object, so a file that does not mention it cannot have come
# from the node's packet filter. The question does not prescribe a tool, so the
# check does not either -- only that the real rules are in the file.

NAMESPACE="svc-iptables"
SERVICE="apronctl"
FILE="/tmp/exam/q17/rules.txt"

if [[ -f /tmp/exam/node-ssh-unavailable ]]; then
    echo "❌ There is no shell on the cluster nodes, so this question cannot be graded."
    exit 1
fi
if [[ ! -s "$FILE" ]]; then
    echo "❌ '$FILE' is missing or empty"
    exit 1
fi

CLUSTER_IP=$(kubectl get service "$SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
if [[ -z "$CLUSTER_IP" || "$CLUSTER_IP" == "None" ]]; then
    echo "❌ Service '$SERVICE' has no cluster IP, so there are no rules to capture"
    exit 1
fi

if ! grep -qF -- "$CLUSTER_IP" "$FILE"; then
    echo "❌ '$FILE' does not mention the Service's cluster IP (${CLUSTER_IP})"
    exit 1
fi

if ! grep -qF -- "${NAMESPACE}/${SERVICE}" "$FILE"; then
    echo "❌ '$FILE' carries no rule commented for '${NAMESPACE}/${SERVICE}'"
    exit 1
fi

if ! grep -qE -- '-A |KUBE-|chain |jump ' "$FILE"; then
    echo "❌ '$FILE' does not look like packet filter rules from a node"
    exit 1
fi

echo "✅ '$FILE' holds the node's rules for the '$SERVICE' Service"
exit 0
