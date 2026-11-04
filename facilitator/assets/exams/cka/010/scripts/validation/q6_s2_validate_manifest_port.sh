#!/bin/bash
set -e

POD_BASE="edge-cache"
HOST_PORT=8080

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes node01 true >/dev/null 2>&1; then
    echo "❌ Cannot reach node01 over SSH"
    exit 1
fi

# Read the directory from the kubelet's own configuration rather than assuming
# /etc/kubernetes/manifests -- that is what the candidate had to do too.
STATIC_DIR=$(ssh -o ConnectTimeout=10 node01 \
    "grep -E '^staticPodPath:' /var/lib/kubelet/config.yaml 2>/dev/null | awk '{print \$2}'" || true)
STATIC_DIR=${STATIC_DIR:-/etc/kubernetes/manifests}

if ! ssh -o ConnectTimeout=10 node01 "grep -lE 'name: *${POD_BASE}\$' ${STATIC_DIR}/*.y*ml >/dev/null 2>&1"; then
    echo "❌ No manifest naming '$POD_BASE' under ${STATIC_DIR} on node01"
    exit 1
fi

BODY=$(ssh -o ConnectTimeout=10 node01 "curl -s --max-time 5 http://localhost:${HOST_PORT}/" 2>/dev/null || true)
if ! grep -qi "nginx" <<<"$BODY"; then
    echo "❌ http://localhost:${HOST_PORT} on node01 does not answer with the nginx page"
    exit 1
fi

echo "✅ The manifest lives in ${STATIC_DIR} and port ${HOST_PORT} on node01 serves nginx"
exit 0
