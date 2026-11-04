#!/bin/bash
set -e

EXPECTED="VersionTLS12"

# Read the flag off the running Pod rather than the manifest: a manifest the
# kubelet has not accepted yet is not a configured API server.
ARGS=$(kubectl get pods -n kube-system -l component=kube-apiserver \
    -o jsonpath='{.items[0].spec.containers[0].command}' 2>/dev/null || true)
if [[ -z "$ARGS" ]]; then
    echo "❌ No kube-apiserver Pod found in kube-system"
    exit 1
fi

if ! grep -q -- "--tls-min-version=$EXPECTED" <<<"$ARGS"; then
    FOUND=$(grep -o -- '--tls-min-version=[^"]*' <<<"$ARGS" || true)
    echo "❌ kube-apiserver runs with '${FOUND:-no --tls-min-version flag}', expected '--tls-min-version=$EXPECTED'"
    exit 1
fi

echo "✅ kube-apiserver runs with --tls-min-version=$EXPECTED"
exit 0
