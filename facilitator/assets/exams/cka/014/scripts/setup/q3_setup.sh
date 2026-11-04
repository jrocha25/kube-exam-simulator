#!/bin/bash
set -e

# Question 3, on the auxiliary cluster: etcd was moved to listen for clients on
# the node's own address only (deliberately), and the API server was "updated to
# match" with the peer port instead of the client port. The etcd change is
# intended and must stay; only the API server is wrong.
#
# Runs after q11_setup.sh, which needs this cluster's API server to remove Calico.

export KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

if [ -f /tmp/exam/aux-cluster-unavailable ]; then
    echo "WARNING: the auxiliary cluster is unavailable, skipping setup for question 3"
    exit 0
fi

ssh -o ConnectTimeout=10 aux 'bash -s' <<'REMOTE'
set -e
ETCD=/etc/kubernetes/manifests/etcd.yaml
APISERVER=/etc/kubernetes/manifests/kube-apiserver.yaml
IP=$(sed -n 's#^\s*- --advertise-client-urls=https://\([0-9.]*\):2379$#\1#p' "$ETCD")
if [ -z "$IP" ]; then
    echo "WARNING: could not read the node address from $ETCD"
    exit 0
fi

# No backups on the node: a copy of the original manifest is the answer.
sed -i "s#^\(\s*- --listen-client-urls=\).*#\1https://${IP}:2379#" "$ETCD"
grep -q -- "--listen-client-urls=https://${IP}:2379$" "$ETCD" \
    || echo "WARNING: --listen-client-urls was not rewritten in $ETCD"

sed -i "s#^\(\s*- --etcd-servers=\).*#\1https://${IP}:2380#" "$APISERVER"
grep -q -- "--etcd-servers=https://${IP}:2380$" "$APISERVER" \
    || echo "WARNING: --etcd-servers was not rewritten in $APISERVER"
REMOTE

DOWN=no
for _ in $(seq 1 24); do
    sleep 5
    if ! kubectl --request-timeout=5s get --raw /readyz >/dev/null 2>&1; then
        DOWN=yes
        break
    fi
done
[ "$DOWN" = yes ] || echo "WARNING: the auxiliary API server still answers after the fault was planted"

echo "Setup for question 3 completed"
