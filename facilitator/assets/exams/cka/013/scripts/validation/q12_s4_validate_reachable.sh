#!/bin/bash
set -e

NAMESPACE="net-orbit"

GW=$(kubectl get service orbit-gw -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
LEGACY=$(kubectl get service orbit-legacy -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)

if [[ "$GW" != 10.250.0.* || "$LEGACY" != 10.250.0.* ]]; then
    echo "❌ orbit-gw ($GW) and orbit-legacy ($LEGACY) are not both in 10.250.0.0/24"
    exit 1
fi

for target in "$GW:80" "$LEGACY:8080"; do
    OK=no
    for _ in $(seq 1 4); do
        if kubectl exec -n "$NAMESPACE" orbit-probe -- wget -qO- -T 3 "http://$target/" 2>/dev/null | grep -q 'Welcome to nginx'; then
            OK=yes
            break
        fi
        sleep 3
    done
    if [[ "$OK" != yes ]]; then
        echo "❌ orbit-probe cannot reach $target"
        exit 1
    fi
done

echo "✅ orbit-gw and orbit-legacy both answer from orbit-probe"
exit 0
