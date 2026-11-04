#!/bin/bash
set -e

# Question 14: a local PersistentVolume pinned by a node label rather than a
# hostname. The Pod is forbidden any placement of its own, so the PV's node
# affinity is the only thing that can put it on the right node -- which is the
# idea being graded. The token is random so that a Pod reading it is proof the
# volume really is that directory on that node.

NAMESPACE="stor-vault"
VAULT_DIR=/srv/ck-x/tidevault
STATE_DIR=/tmp/exam/q14

mkdir -p "$STATE_DIR"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

NODE01=$(grep '^node01=' /tmp/exam/nodes.env | cut -d= -f2)
kubectl label node "$NODE01" storage.ck-x.io/vault=nvme --overwrite >/dev/null

if [ -f /tmp/exam/node-ssh-unavailable ]; then
    echo "WARNING: skipping question 14 setup, there is no shell on the nodes"
    exit 0
fi

TOKEN=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
ssh -n -o ConnectTimeout=10 node01 "mkdir -p $VAULT_DIR && echo $TOKEN > $VAULT_DIR/token && chmod 644 $VAULT_DIR/token"
echo "$TOKEN" | sha256sum | awk '{print $1}' > "$STATE_DIR/token.sha256"

echo "Setup completed for Question 14"
