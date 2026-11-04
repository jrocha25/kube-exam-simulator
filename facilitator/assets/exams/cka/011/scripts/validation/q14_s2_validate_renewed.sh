#!/bin/bash
set -e

# "Renewed" means the certificate's notBefore moved forward from where it was
# when the lab warmed up. The baseline is re-recorded on every warm-up, so a
# renewal carried over from a previous attempt does not count.

CERT="/etc/kubernetes/pki/apiserver-kubelet-client.crt"
BASELINE="/tmp/exam/q14/baseline-apiserver-kubelet-client"

if [[ -f /tmp/exam/node-ssh-unavailable ]]; then
    echo "❌ There is no shell on the cluster nodes, so this question cannot be graded."
    exit 1
fi
if [[ ! -s "$BASELINE" ]]; then
    echo "❌ No baseline was recorded during setup, so a renewal cannot be detected"
    exit 1
fi

CURRENT=$(ssh -o ConnectTimeout=10 -o BatchMode=yes controlplane \
    "openssl x509 -noout -startdate -in ${CERT}" 2>/dev/null | tr -d '\r' | cut -d= -f2-)
if [[ -z "$CURRENT" ]]; then
    echo "❌ Could not read ${CERT} on the control plane node"
    exit 1
fi

BEFORE=$(cat "$BASELINE")
BEFORE_EPOCH=$(date -d "$BEFORE" +%s 2>/dev/null || echo "")
CURRENT_EPOCH=$(date -d "$CURRENT" +%s 2>/dev/null || echo "")

if [[ -z "$BEFORE_EPOCH" || -z "$CURRENT_EPOCH" ]]; then
    echo "❌ Could not interpret the certificate dates ('${BEFORE}' / '${CURRENT}')"
    exit 1
fi

if [[ "$CURRENT_EPOCH" -le "$BEFORE_EPOCH" ]]; then
    echo "❌ The apiserver-kubelet-client certificate still dates from ${BEFORE}; it has not been renewed"
    exit 1
fi

echo "✅ The apiserver-kubelet-client certificate was renewed"
exit 0
