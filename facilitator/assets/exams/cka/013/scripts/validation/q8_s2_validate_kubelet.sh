#!/bin/bash
set -e

NODE03=$(grep '^node03=' /tmp/exam/nodes.env | cut -d= -f2)
CLIENT_CERT=/var/lib/kubelet/pki/kubelet-client-current.pem

READY=$(kubectl get node "$NODE03" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
if [[ "$READY" != "True" ]]; then
    echo "❌ node03 is not Ready"
    exit 1
fi

STATE=$(ssh -n -o ConnectTimeout=10 -o BatchMode=yes node03 \
    'echo "$(systemctl is-active kubelet) $(systemctl is-enabled kubelet)"' 2>/dev/null || true)
if [[ "$STATE" != "active enabled" ]]; then
    echo "❌ node03's kubelet is '${STATE:-unknown}', expected active and enabled"
    exit 1
fi

# The node must still authenticate as itself: the kubeconfig the kubelet uses
# has to carry the node's own rotating client certificate, not admin.conf's.
CERT=$(ssh -n -o ConnectTimeout=10 -o BatchMode=yes node03 \
    "awk '/client-certificate:/ {print \$2}' /etc/kubernetes/kubelet.conf" 2>/dev/null || true)
if [[ "$CERT" != "$CLIENT_CERT" ]]; then
    echo "❌ node03's kubelet.conf no longer uses the node's own client certificate"
    exit 1
fi

echo "✅ node03's kubelet is active, enabled and authenticates as the node"
exit 0
