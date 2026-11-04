#!/bin/bash
set -e

# Question 14: read one certificate, renew exactly one other.
#
# "Renewed" and "left alone" are both relative to the moment the lab warmed up,
# so the current notBefore of every certificate the question talks about is
# recorded here. Re-recording on every warm-up is what keeps the question honest
# across repeated attempts: a candidate who renewed last time still has to renew
# again, because the baseline moved with them.

NAMESPACE="certs-tower"
DIR="/tmp/exam/q14"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

mkdir -p "$DIR"
rm -f "${DIR}/etcd-expiry.txt" "${DIR}"/baseline-*

if [ -f /tmp/exam/node-ssh-unavailable ]; then
    echo "WARNING: there is no shell on the nodes, skipping setup for question 14"
    exit 0
fi

record() {
    local name="$1" path="$2" value
    value=$(ssh -o ConnectTimeout=10 -o BatchMode=yes controlplane \
        "openssl x509 -noout -startdate -in ${path} 2>/dev/null | cut -d= -f2-" 2>/dev/null || true)
    if [ -n "$value" ]; then
        printf '%s\n' "$value" > "${DIR}/baseline-${name}"
        echo "baseline ${name}: ${value}"
    else
        echo "WARNING: could not read ${path} on the control plane node"
    fi
}

record apiserver-kubelet-client /etc/kubernetes/pki/apiserver-kubelet-client.crt
record apiserver               /etc/kubernetes/pki/apiserver.crt
record front-proxy-client      /etc/kubernetes/pki/front-proxy-client.crt
record etcd-server             /etc/kubernetes/pki/etcd/server.crt

echo "Setup completed for Question 14"
