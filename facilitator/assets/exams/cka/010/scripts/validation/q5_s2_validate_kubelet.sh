#!/bin/bash
set -e

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes node02 true >/dev/null 2>&1; then
    echo "❌ Cannot reach node02 over SSH"
    exit 1
fi

ACTIVE=$(ssh -o ConnectTimeout=10 node02 "systemctl is-active kubelet" 2>/dev/null || true)
if [[ "$ACTIVE" != "active" ]]; then
    echo "❌ The kubelet on node02 is '${ACTIVE:-unknown}', expected active"
    exit 1
fi

ENABLED=$(ssh -o ConnectTimeout=10 node02 "systemctl is-enabled kubelet" 2>/dev/null || true)
if [[ "$ENABLED" != "enabled" ]]; then
    echo "❌ The kubelet on node02 is '${ENABLED:-unknown}', expected enabled"
    exit 1
fi

echo "✅ The kubelet on node02 is active and enabled"
exit 0
