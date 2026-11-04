#!/bin/bash
set -e

STATE=$(ssh -o ConnectTimeout=10 -o BatchMode=yes node03 \
    'echo $(systemctl is-enabled kubelet 2>/dev/null)/$(systemctl is-active kubelet 2>/dev/null)' 2>/dev/null </dev/null || true)
if [[ "$STATE" != "enabled/active" ]]; then
    echo "❌ The kubelet on node03 must be running and enabled at boot (is-enabled/is-active: '${STATE:-unknown}')"
    exit 1
fi

# The unit has to start a binary that exists, or the next reboot brings the
# fault straight back even with the unit enabled.
EXEC=$(ssh -o ConnectTimeout=10 -o BatchMode=yes node03 \
    "systemctl show kubelet -p ExecStart --value | sed -n 's/.*path=\([^ ;]*\).*/\1/p' | head -1" 2>/dev/null </dev/null || true)
if [[ -z "$EXEC" ]] || ! ssh -o ConnectTimeout=10 -o BatchMode=yes node03 "test -x '$EXEC'" </dev/null 2>/dev/null; then
    echo "❌ The kubelet unit on node03 starts '${EXEC:-?}', which is not an executable"
    exit 1
fi

echo "✅ The kubelet on node03 is enabled, running, and starts $EXEC"
exit 0
