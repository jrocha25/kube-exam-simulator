#!/bin/bash
set -e

ORIG=/tmp/exam/q5/config.yaml.orig
CP=$(grep '^controlplane=' /tmp/exam/nodes.env | cut -d= -f2)

# A constraint: only meaningful once the cluster-wide change is in place.
DATA=$(kubectl get configmap kubelet-config -n kube-system -o jsonpath='{.data.kubelet}' 2>/dev/null || true)
if ! echo "$DATA" | grep -Eq '^containerLogMaxSize: "?25Mi"?$'; then
    echo "❌ The cluster-wide kubelet configuration has not been changed yet"
    exit 1
fi

if [[ ! -s "$ORIG" ]]; then
    echo "❌ Setup did not record controlplane's kubelet configuration, so this step cannot be graded"
    exit 1
fi

CURRENT=$(ssh -n -o ConnectTimeout=10 -o BatchMode=yes controlplane 'cat /var/lib/kubelet/config.yaml' 2>/dev/null || true)
if [[ -z "$CURRENT" ]]; then
    echo "❌ Cannot read /var/lib/kubelet/config.yaml on controlplane"
    exit 1
fi
if ! diff <(grep -Ev '^containerLogMax(Size|Files):|^\s*$' "$ORIG" | sort) \
          <(echo "$CURRENT" | grep -Ev '^containerLogMax(Size|Files):|^\s*$' | sort) >/dev/null; then
    echo "❌ controlplane's kubelet configuration changed in more than the two log rotation settings"
    exit 1
fi

READY=$(kubectl get node "$CP" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
if [[ "$READY" != "True" ]]; then
    echo "❌ controlplane is not Ready"
    exit 1
fi

echo "✅ Nothing else in controlplane's kubelet configuration changed and the node is Ready"
exit 0
