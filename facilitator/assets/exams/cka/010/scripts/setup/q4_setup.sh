#!/bin/bash
set -e

# Question 4: renew the control plane certificates with kubeadm. Nothing is
# broken here -- the question is the procedure -- so setup only records what
# "before" looks like, for the validation scripts to compare against:
#
#   * the NotAfter of three kubeadm-managed certificates under /etc/kubernetes/pki
#   * the NotAfter of the client certificates embedded in two of the kubeconfigs
#     under /etc/kubernetes ("kubeadm certs renew all" rotates those too)
#   * the time, so "the components were restarted" can be graded as a container
#     start after setup
#
# All read over SSH from the control plane; the certificate the API server
# *serves* is compared live by q4_s2 from the jumphost.

mkdir -p /tmp/exam/q4
rm -f /tmp/exam/q4/*

if [ -f /tmp/exam/node-ssh-unavailable ]; then
    echo "WARNING: skipping question 4 setup, there is no shell on the nodes"
    exit 0
fi

ssh -o ConnectTimeout=10 controlplane 'bash -s' <<'REMOTE' > /tmp/exam/q4/before.env
for cert in apiserver apiserver-kubelet-client front-proxy-client; do
    end=$(openssl x509 -in "/etc/kubernetes/pki/${cert}.crt" -noout -enddate 2>/dev/null | cut -d= -f2)
    [ -n "$end" ] && echo "${cert//-/_}=$(date -d "$end" +%s)"
done
for conf in controller-manager scheduler; do
    end=$(grep client-certificate-data "/etc/kubernetes/${conf}.conf" | awk '{print $2}' | base64 -d \
        | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    [ -n "$end" ] && echo "${conf//-/_}_conf=$(date -d "$end" +%s)"
done
echo "setup_time=$(date +%s)"
REMOTE

if ! grep -q '^apiserver=' /tmp/exam/q4/before.env; then
    echo "WARNING: could not read the API server certificate on the control plane"
fi
echo "Recorded certificate expiry dates:"
cat /tmp/exam/q4/before.env

echo "Setup completed for Question 4"
