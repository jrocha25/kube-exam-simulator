#!/bin/bash
set -e

EXPECTED="TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256"

ARGS=$(kubectl get pods -n kube-system -l component=kube-apiserver \
    -o jsonpath='{.items[0].spec.containers[0].command}' 2>/dev/null || true)
if [[ -z "$ARGS" ]]; then
    echo "❌ No kube-apiserver Pod found in kube-system"
    exit 1
fi

FOUND=$(grep -o -- '--tls-cipher-suites=[^"]*' <<<"$ARGS" | head -1 | cut -d= -f2- || true)
if [[ -z "$FOUND" ]]; then
    echo "❌ kube-apiserver has no --tls-cipher-suites flag"
    exit 1
fi

if [[ "$FOUND" != "$EXPECTED" ]]; then
    echo "❌ kube-apiserver offers '$FOUND'"
    echo "   expected exactly '$EXPECTED', in that order"
    exit 1
fi

echo "✅ kube-apiserver offers exactly the approved cipher suites"
exit 0
