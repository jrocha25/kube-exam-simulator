#!/bin/bash
set -e

# Question 1: a static Pod on node01 carrying two independent faults, both of the
# kind that a mirror pod hides rather than reports:
#
#   1. the hostPath source has a typo. type: DirectoryOrCreate means the kubelet
#      happily creates the empty directory instead of refusing, so the volume
#      mounts cleanly and the files are simply not there.
#   2. the command reads a config file whose name does not match what is on disk
#      (probe.cfg vs probe.conf), so even a correct hostPath would still fail.
#
# Fixing only one leaves the Pod crashing, which is the point: the candidate has
# to read the container's own output rather than stop at the first thing that
# looks wrong.

NAMESPACE="ops-probe"
[ -f /tmp/exam/nodes.env ] && . /tmp/exam/nodes.env

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

if [ -f /tmp/exam/node-ssh-unavailable ]; then
    echo "WARNING: skipping question 1 setup, there is no shell on the nodes"
    exit 0
fi

ssh -o ConnectTimeout=10 node01 'bash -s' <<'REMOTE'
set -e
rm -rf /opt/probe-data
mkdir -p /opt/probe-data
cat > /opt/probe-data/probe.conf <<'CFG'
interval=30
endpoint=127.0.0.1:9101
CFG

cat > /etc/kubernetes/manifests/node-probe.yaml <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: node-probe
  namespace: ops-probe
  labels:
    app: node-probe
spec:
  containers:
  - name: probe
    image: busybox:1.36
    command:
    - sh
    - -c
    - "cat /etc/probe/probe.cfg && echo probe started && sleep 86400"
    volumeMounts:
    - name: config
      mountPath: /etc/probe
  volumes:
  - name: config
    hostPath:
      path: /opt/probe-datta
      type: DirectoryOrCreate
YAML
REMOTE

echo "Setup completed for Question 1"
