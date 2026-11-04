#!/bin/bash
set -e

NAMESPACE="logistics"
DEPLOYMENT="shipment-tracker"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

MAIN_IMAGE=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json \
    | jq -r '[.spec.template.spec.containers[] | select(.name == "tracker") | .image] | first // empty')
if [[ "$MAIN_IMAGE" != "busybox:1.36" ]]; then
    echo "❌ The existing container 'tracker' must keep the image 'busybox:1.36' (got: '${MAIN_IMAGE:-<none>}')"
    exit 1
fi

DESIRED=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.spec.replicas}')

READY=""
for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)
    if [[ "$READY" == "$DESIRED" ]]; then
        break
    fi
    sleep 5
done

if [[ "$READY" != "$DESIRED" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' did not roll out. Ready: '${READY:-0}', expected: '$DESIRED'"
    exit 1
fi

RUNNING_SIDECARS=$(kubectl get pods -n "$NAMESPACE" -l app=shipment-tracker -o json \
    | jq '[.items[]
        | select(.status.phase == "Running")
        | (.status.initContainerStatuses // [])[]
        | select(.name == "log-shipper" and .started == true)] | length')

if [[ "$RUNNING_SIDECARS" -lt "$DESIRED" ]]; then
    echo "❌ Only $RUNNING_SIDECARS of $DESIRED Pods run a started 'log-shipper' sidecar"
    exit 1
fi

echo "✅ Deployment '$DEPLOYMENT' rolled out with all $DESIRED replicas ready and the sidecar running"
exit 0
