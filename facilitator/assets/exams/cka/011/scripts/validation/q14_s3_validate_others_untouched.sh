#!/bin/bash
set -e

# A constraint check: "kubeadm certs renew all" would satisfy the renewal check
# above while quietly rewriting the whole PKI, so the other certificates have to
# still carry the issue date they had at warm-up. This passes on an untouched
# cluster by design and is worth one mark.

if [[ -f /tmp/exam/node-ssh-unavailable ]]; then
    echo "❌ There is no shell on the cluster nodes, so this question cannot be graded."
    exit 1
fi

check() {
    local name="$1" path="$2" baseline current
    baseline="/tmp/exam/q14/baseline-${name}"
    if [[ ! -s "$baseline" ]]; then
        echo "❌ No baseline was recorded for ${name} during setup"
        return 1
    fi
    current=$(ssh -o ConnectTimeout=10 -o BatchMode=yes controlplane \
        "openssl x509 -noout -startdate -in ${path}" 2>/dev/null | tr -d '\r' | cut -d= -f2-)
    if [[ -z "$current" ]]; then
        echo "❌ Could not read ${path} on the control plane node"
        return 1
    fi
    if [[ "$current" != "$(cat "$baseline")" ]]; then
        echo "❌ The ${name} certificate was renewed too; only apiserver-kubelet-client was to be touched"
        return 1
    fi
    return 0
}

check apiserver          /etc/kubernetes/pki/apiserver.crt          || exit 1
check front-proxy-client /etc/kubernetes/pki/front-proxy-client.crt || exit 1
check etcd-server        /etc/kubernetes/pki/etcd/server.crt        || exit 1

echo "✅ The other control plane certificates were left alone"
exit 0
