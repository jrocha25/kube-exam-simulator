#!/bin/bash
set -e

CP=$(grep '^controlplane=' /tmp/exam/nodes.env | cut -d= -f2)

# /configz is what the running kubelet loaded, so a file edited on disk without a
# restart does not count. A kubelet restarted a moment ago may still be coming up.
for _ in $(seq 1 6); do
    CONFIGZ=$(kubectl get --raw "/api/v1/nodes/${CP}/proxy/configz" 2>/dev/null || true)
    [[ -n "$CONFIGZ" ]] && break
    sleep 5
done
if [[ -z "$CONFIGZ" ]]; then
    echo "❌ The kubelet on controlplane does not answer"
    exit 1
fi

SIZE=$(echo "$CONFIGZ" | jq -r '.kubeletconfig.containerLogMaxSize')
FILES=$(echo "$CONFIGZ" | jq -r '.kubeletconfig.containerLogMaxFiles')
if [[ "$SIZE" != "25Mi" || "$FILES" != "4" ]]; then
    echo "❌ controlplane's kubelet runs with containerLogMaxSize=$SIZE and containerLogMaxFiles=$FILES"
    exit 1
fi

echo "✅ controlplane's kubelet runs with containerLogMaxSize=25Mi and containerLogMaxFiles=4"
exit 0
