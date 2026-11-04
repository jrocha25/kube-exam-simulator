#!/bin/bash
set -e

ORIG=/tmp/exam/q5/configmap.orig

if [[ ! -s "$ORIG" ]]; then
    echo "❌ Setup did not record the kubelet-config ConfigMap, so this step cannot be graded"
    exit 1
fi

DATA=$(kubectl get configmap kubelet-config -n kube-system -o jsonpath='{.data.kubelet}' 2>/dev/null || true)
if [[ -z "$DATA" ]]; then
    echo "❌ The kubelet-config ConfigMap in kube-system is missing or empty"
    exit 1
fi

if ! echo "$DATA" | grep -Eq '^containerLogMaxSize: "?25Mi"?$'; then
    echo "❌ kubelet-config does not set containerLogMaxSize: 25Mi"
    exit 1
fi
if ! echo "$DATA" | grep -Eq '^containerLogMaxFiles: 4$'; then
    echo "❌ kubelet-config does not set containerLogMaxFiles: 4"
    exit 1
fi

# Everything else must be as it was. Compare with the two keys removed, and
# ignore ordering and blank lines so that kubectl edit's reformatting is fine.
NORMALISE='grep -Ev "^containerLogMax(Size|Files):|^\s*$" | sort'
if ! diff <(eval "cat '$ORIG' | $NORMALISE") <(eval "echo \"\$DATA\" | $NORMALISE") >/dev/null; then
    echo "❌ kubelet-config changed in more than the two log rotation settings"
    exit 1
fi

echo "✅ kubelet-config carries the two log rotation settings and nothing else changed"
exit 0
