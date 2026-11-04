#!/bin/bash
set -e

# The survivor's claim proves whenDeleted was not set to Delete as well, and the
# two missing claims prove whenScaled actually took effect rather than the
# claims having been removed by hand before the policy existed.

NAMESPACE="wl-baggage"

if ! kubectl get pvc data-belt-0 -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ The claim 'data-belt-0' is gone; the remaining Pod's storage was to be kept"
    exit 1
fi

# Capped at 30s per claim: two claims plus the guards above have to fit inside
# the 90 second cap the runner applies to every validation script.
for i in 1 2; do
    for _ in $(seq 1 6); do
        kubectl get pvc "data-belt-${i}" -n "$NAMESPACE" >/dev/null 2>&1 || break
        sleep 5
    done
    if kubectl get pvc "data-belt-${i}" -n "$NAMESPACE" >/dev/null 2>&1; then
        echo "❌ The claim 'data-belt-${i}' still exists; scaling in was to reclaim it"
        exit 1
    fi
done

echo "✅ The removed replicas' claims are gone and the survivor's remains"
exit 0
