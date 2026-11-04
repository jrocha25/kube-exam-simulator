#!/bin/bash

set -e

# Proves the size change was scoped to one of the two composed bases. Mechanism
# is deliberately not graded -- a patch and the replicas transformer are both
# legitimate answers, and the skill under test is composition.

NAMESPACE="kustom-compose"

CACHE=$(kubectl get deployment waybill-cache -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2> /dev/null || true)
if [[ "$CACHE" != "2" ]]; then
    echo "❌ 'waybill-cache' declares ${CACHE:-no} replicas, expected 2"
    exit 1
fi

API=$(kubectl get deployment waybill-api -n "$NAMESPACE" -o jsonpath='{.spec.replicas}' 2> /dev/null || true)
if [[ "$API" != "1" ]]; then
    echo "❌ 'waybill-api' declares ${API:-no} replicas, expected 1; the change was not scoped to the cache"
    exit 1
fi

echo "✅ The cache runs 2 replicas while the api base is left at 1"
exit 0
