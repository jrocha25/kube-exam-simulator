#!/bin/bash
set -e

# Question 6: a static Pod on node01. Nothing to stage beyond the namespace the
# mirror Pod has to land in -- a static Pod whose manifest names a namespace that
# does not exist runs fine on the node but never gets a mirror Pod through the
# API server, which would make a correct answer look wrong.

NAMESPACE="static-edge"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Clear anything a previous attempt left on the node.
if [ ! -f /tmp/exam/node-ssh-unavailable ]; then
    ssh -o ConnectTimeout=10 node01 "rm -f /etc/kubernetes/manifests/edge-cache.yaml" 2>/dev/null || true
fi

echo "Setup completed for Question 6"
