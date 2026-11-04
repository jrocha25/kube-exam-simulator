#!/bin/bash
set -e

NAMESPACE="rbac-token"
POD="probe"
SA="job-runner"

if ! kubectl get pod "$POD" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Pod '$POD' not found in namespace '$NAMESPACE'"
    exit 1
fi

POD_SA=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.serviceAccountName}')
if [[ "$POD_SA" != "$SA" ]]; then
    echo "❌ Pod '$POD' runs as ServiceAccount '${POD_SA:-<none>}', expected '$SA'"
    exit 1
fi

AUTOMOUNT=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.automountServiceAccountToken}')
if [[ "$AUTOMOUNT" != "true" ]]; then
    echo "❌ Pod '$POD' has automountServiceAccountToken '${AUTOMOUNT:-<unset>}', expected 'true' to override the ServiceAccount"
    exit 1
fi

# The override only means anything if the token really is projected into the container.
MOUNTED=$(kubectl get pod "$POD" -n "$NAMESPACE" -o json | jq '[.spec.volumes[]? | select(.projected.sources[]?.serviceAccountToken != null)] | length')
if [[ "$MOUNTED" == "0" ]]; then
    echo "❌ Pod '$POD' has no projected ServiceAccount token volume"
    exit 1
fi

for _ in $(seq 1 12); do
    PHASE=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    [[ "$PHASE" == "Running" ]] && break
    sleep 5
done
if [[ "$PHASE" != "Running" ]]; then
    echo "❌ Pod '$POD' is '$PHASE', expected 'Running'"
    exit 1
fi

echo "✅ Pod '$POD' runs as '$SA' and mounts its token despite the ServiceAccount opting out"
exit 0
