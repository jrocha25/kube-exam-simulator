#!/bin/bash
set -e

STATE_FILE=/tmp/exam/q4/scheduler.uid
CP=$(grep '^controlplane=' /tmp/exam/nodes.env | cut -d= -f2)
POD="kube-scheduler-${CP}"

if [[ ! -s "$STATE_FILE" ]]; then
    echo "❌ Setup did not record the scheduler, so this step cannot be graded"
    exit 1
fi

for _ in $(seq 1 6); do
    READY=$(kubectl get pod "$POD" -n kube-system -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    [[ "$READY" == "True" ]] && break
    sleep 5
done
if [[ "$READY" != "True" ]]; then
    echo "❌ The kube-scheduler Pod '$POD' is not running and Ready"
    exit 1
fi

# The kubelet deletes the mirror Pod when its manifest goes away and creates a
# new one when it comes back, so a changed UID means the static Pod was stopped.
CURRENT=$(kubectl get pod "$POD" -n kube-system -o jsonpath='{.metadata.uid}')
if [[ "$CURRENT" == "$(cat "$STATE_FILE")" ]]; then
    echo "❌ The kube-scheduler static Pod was never stopped"
    exit 1
fi

echo "✅ The scheduler was stopped, started again and is Ready"
exit 0
