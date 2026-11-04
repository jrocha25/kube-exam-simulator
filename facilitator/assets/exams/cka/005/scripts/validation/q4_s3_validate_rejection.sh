#!/bin/bash
set -e

NAMESPACE="registry-audit"
PROBE_POD="limit-probe"

if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
    echo "❌ Namespace '$NAMESPACE' not found"
    exit 1
fi

# --dry-run=server runs the full admission chain, LimitRanger included, without
# persisting anything -- so this stays a read only check of the namespace policy.
PROBE_MANIFEST=$(cat <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: $PROBE_POD
  namespace: $NAMESPACE
spec:
  containers:
  - name: probe
    image: nginx:1.27.4
    resources:
      limits:
        memory: 1Gi
YAML
)

if OUTPUT=$(echo "$PROBE_MANIFEST" | kubectl create -f - --dry-run=server 2>&1); then
    echo "❌ A Pod with a 1Gi memory limit was accepted by namespace '$NAMESPACE'"
    echo "$OUTPUT"
    exit 1
fi

if ! echo "$OUTPUT" | grep -qi "maximum memory"; then
    echo "❌ The Pod was refused, but not by a memory maximum in the namespace policy:"
    echo "$OUTPUT"
    exit 1
fi

echo "✅ A Pod requesting a 1Gi memory limit is refused by the '$NAMESPACE' policy"
exit 0
