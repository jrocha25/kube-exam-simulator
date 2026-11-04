#!/bin/bash
set -e

# The etcd change was deliberate: etcd now serves clients on the node address
# only, and the API server has to follow it on the client port.
export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

if [[ -f /tmp/exam/aux-cluster-unavailable ]]; then
    echo "❌ The auxiliary cluster was not available for this exam"
    exit 1
fi

MANIFESTS=$(ssh -o ConnectTimeout=10 -o BatchMode=yes aux \
    'cat /etc/kubernetes/manifests/etcd.yaml; echo "---8<---"; cat /etc/kubernetes/manifests/kube-apiserver.yaml' 2>/dev/null </dev/null || true)
if [[ -z "$MANIFESTS" ]]; then
    echo "❌ Cannot read the static Pod manifests on the auxiliary node"
    exit 1
fi
ETCD=${MANIFESTS%%---8<---*}
APISERVER=${MANIFESTS##*---8<---}

IP=$(echo "$ETCD" | sed -n 's#^\s*- --advertise-client-urls=https://\([0-9.]*\):2379$#\1#p')
LISTEN=$(echo "$ETCD" | sed -n 's#^\s*- --listen-client-urls=\(.*\)$#\1#p')
SERVERS=$(echo "$APISERVER" | sed -n 's#^\s*- --etcd-servers=\(.*\)$#\1#p')

if [[ -z "$IP" ]]; then
    echo "❌ etcd.yaml no longer advertises a client URL on the node address"
    exit 1
fi
if [[ "$LISTEN" != "https://${IP}:2379" ]]; then
    echo "❌ etcd's client listener was changed back (--listen-client-urls=$LISTEN); it must stay on https://${IP}:2379 only"
    exit 1
fi
if [[ "$SERVERS" != "https://${IP}:2379" ]]; then
    echo "❌ The API server's --etcd-servers is '$SERVERS', expected https://${IP}:2379"
    exit 1
fi

if ! kubectl --request-timeout=10s get --raw /readyz >/dev/null 2>&1; then
    echo "❌ The manifests look right but the API server does not answer"
    exit 1
fi

echo "✅ The API server reaches etcd on its client port at the node address, and etcd was left as reconfigured"
exit 0
