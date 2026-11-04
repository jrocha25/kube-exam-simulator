#!/bin/bash
set -e

NAMESPACE="qos-hangar"
DEPLOYMENT="hangar-ops"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" >/dev/null 2>&1; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

for _ in $(seq 1 12); do
    CLASSES=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" \
        --field-selector=status.phase=Running \
        -o jsonpath='{range .items[*]}{.status.qosClass}{"\n"}{end}' 2>/dev/null | grep -c . || true)
    GUARANTEED=$(kubectl get pods -n "$NAMESPACE" -l app="$DEPLOYMENT" \
        --field-selector=status.phase=Running \
        -o jsonpath='{range .items[*]}{.status.qosClass}{"\n"}{end}' 2>/dev/null | grep -c '^Guaranteed$' || true)
    [[ "${CLASSES:-0}" -ge 2 && "${GUARANTEED:-0}" == "${CLASSES:-0}" ]] && break
    sleep 5
done

if [[ "${CLASSES:-0}" -lt 2 ]]; then
    echo "❌ Found ${CLASSES:-0} running '$DEPLOYMENT' Pods, expected 2"
    exit 1
fi
if [[ "${GUARANTEED:-0}" != "${CLASSES}" ]]; then
    echo "❌ ${GUARANTEED:-0} of ${CLASSES} running Pods are in the Guaranteed class"
    echo "   Guaranteed needs every container to declare limits, and requests equal to them."
    exit 1
fi

echo "✅ All ${CLASSES} running '$DEPLOYMENT' Pods are Guaranteed"
exit 0
