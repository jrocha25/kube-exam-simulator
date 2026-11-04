#!/bin/bash
set -e

# Question 6: kube-apiserver hardening. Nothing to seed -- the candidate edits the
# live static pod manifest. Setup only removes the flags if a previous attempt
# left them behind, so the question starts from the stock manifest every time.

if [ -f /tmp/exam/node-ssh-unavailable ]; then
    echo "WARNING: skipping question 6 setup, there is no shell on the nodes"
    exit 0
fi

ssh -o ConnectTimeout=10 controlplane 'bash -s' <<'REMOTE'
set -e
MANIFEST=/etc/kubernetes/manifests/kube-apiserver.yaml

# Keep a pristine copy next to the manifest but outside the directory the kubelet
# watches -- dropping a second Pod manifest in /etc/kubernetes/manifests would
# start a second apiserver.
mkdir -p /opt/ck-x-backup
cp -n "$MANIFEST" /opt/ck-x-backup/kube-apiserver.yaml.original 2>/dev/null || true

if grep -q 'tls-min-version\|tls-cipher-suites' "$MANIFEST"; then
    sed -i '/--tls-min-version=/d;/--tls-cipher-suites=/d' "$MANIFEST"
    echo "Removed hardening flags left over from a previous attempt"
fi
REMOTE

echo "Setup completed for Question 6"
