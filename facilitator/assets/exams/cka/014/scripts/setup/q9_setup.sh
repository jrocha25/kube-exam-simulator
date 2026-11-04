#!/bin/bash
set -e

# Question 9: node03 NotReady. Two faults: the kubelet drop-in starts a binary
# that does not exist, and the unit is disabled, so a fix that only restarts it
# does not survive a reboot.
#
# This is the last script in glob order. node03 has been cordoned since q0, so
# nothing else is scheduled there; it is uncordoned once the node is NotReady,
# when the node.kubernetes.io/not-ready taint keeps everything off instead.

NODE03=$(grep '^node03=' /tmp/exam/nodes.env | cut -d= -f2)
if [ -f /tmp/exam/node-ssh-unavailable ] || [ -z "$NODE03" ]; then
    echo "WARNING: skipping the question 9 faults, there is no shell on node03"
    [ -n "$NODE03" ] && kubectl uncordon "$NODE03" >/dev/null 2>&1 || true
    exit 0
fi

ssh -o ConnectTimeout=10 node03 'bash -s' <<'REMOTE'
set -e
DROPIN=/etc/systemd/system/kubelet.service.d/10-kubeadm.conf
sed -i 's#^ExecStart=/usr/bin/kubelet #ExecStart=/usr/local/bin/kubelet #' "$DROPIN"
grep -q '^ExecStart=/usr/local/bin/kubelet ' "$DROPIN" \
    || echo "WARNING: the kubelet ExecStart line was not found in $DROPIN"
systemctl daemon-reload
systemctl disable kubelet >/dev/null 2>&1 || true
systemctl stop kubelet || true
REMOTE

STAGED=no
for _ in $(seq 1 18); do
    READY=$(kubectl get node "$NODE03" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
    if [ "$READY" != "True" ]; then
        STAGED=yes
        break
    fi
    sleep 5
done
[ "$STAGED" = yes ] || echo "WARNING: node03 still reports Ready; the kubelet faults did not take"

kubectl uncordon "$NODE03" >/dev/null 2>&1 || true

echo "Setup for question 9 completed"
