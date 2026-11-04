#!/bin/bash
set -e

UNIT="harbor-cri-shim"

STATE=$(ssh -o ConnectTimeout=10 -o BatchMode=yes node01 \
    "echo \$(systemctl is-enabled $UNIT 2>/dev/null)/\$(systemctl is-active $UNIT 2>/dev/null)" 2>/dev/null </dev/null || true)
if [[ "$STATE" != "enabled/active" ]]; then
    echo "❌ $UNIT on node01 must be enabled and active (is-enabled/is-active: '${STATE:-unknown}')"
    exit 1
fi

echo "✅ $UNIT is enabled and running on node01"
exit 0
