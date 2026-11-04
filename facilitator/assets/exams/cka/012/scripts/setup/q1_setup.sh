#!/bin/bash
set -e

# Question 1: a static Pod on node02 -- in the directory that node's kubelet is
# actually configured to read.
#
# The point of the question is the step a mock exam marked wrong: the candidate
# put the manifest somewhere plausible instead of where that kubelet reads from.
# On a stock kubeadm node staticPodPath IS /etc/kubernetes/manifests, so asking
# the candidate to "read it from the config" would change nothing and the
# question would collapse into "write a static Pod". So this setup moves it:
# node02's kubelet is reconfigured to read /etc/kubernetes/node-manifests, and a
# manifest dropped into /etc/kubernetes/manifests on that node does nothing at
# all. The validation script reads the path off the node the same way, so it
# grades whatever the node really says.
#
# A worker runs no control-plane static Pods, so restarting its kubelet is cheap
# -- but if it does not come back Ready the whole lab is damaged, so the change
# is reverted on failure.
#
# The namespace is created here on purpose. The kubelet runs a static Pod whether
# or not its namespace exists, but the *mirror* Pod it registers with the API
# server is rejected while the namespace is missing, so the Pod would be running
# on the node and invisible to kubectl -- a confusing way to fail a question
# about where the manifest goes.

NAMESPACE="node-sensor"
POD_BASE="sensor-collector"
TARGET="node02"
STATIC_DIR="/etc/kubernetes/node-manifests"
SSH_OPTS="-o ConnectTimeout=10 -o BatchMode=yes"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

if [ -f /tmp/exam/node-ssh-unavailable ]; then
    echo "WARNING: there is no shell on the nodes, skipping setup for question 1"
    exit 0
fi

node_ready() {
    local alias="$1" name
    name=$(awk -F= -v a="$alias" '$1==a {print $2}' /tmp/exam/nodes.env 2>/dev/null | head -1)
    [ -n "$name" ] || return 1
    [ "$(kubectl get node "$name" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" = "True" ]
}

# ---------------------------------------------------------------------------
# Point node02's kubelet at a directory of its own, idempotently.
# ---------------------------------------------------------------------------
if ! ssh $SSH_OPTS "$TARGET" "STATIC_DIR=${STATIC_DIR} bash -s" <<'REMOTE'
set -e
CFG=/var/lib/kubelet/config.yaml
mkdir -p "$STATIC_DIR"
CURRENT=$(awk '/^staticPodPath:/ {print $2}' "$CFG" 2>/dev/null || true)
if [ "$CURRENT" != "$STATIC_DIR" ]; then
    if grep -q '^staticPodPath:' "$CFG"; then
        sed -i "s|^staticPodPath:.*|staticPodPath: ${STATIC_DIR}|" "$CFG"
    else
        printf 'staticPodPath: %s\n' "$STATIC_DIR" >> "$CFG"
    fi
    systemctl restart kubelet
fi
REMOTE
then
    echo "WARNING: could not reconfigure the kubelet on ${TARGET}; question 1 will"
    echo "WARNING: still be gradeable, but against the default static Pod path."
fi

# The kubelet has to come back. If it does not, put the default back rather than
# leaving a node down for the rest of the exam.
READY=no
for _ in $(seq 1 12); do
    if node_ready "$TARGET"; then READY=yes; break; fi
    sleep 5
done
if [ "$READY" != yes ]; then
    echo "WARNING: ${TARGET} did not return to Ready; reverting its static Pod path"
    ssh $SSH_OPTS "$TARGET" \
        "sed -i 's|^staticPodPath:.*|staticPodPath: /etc/kubernetes/manifests|' /var/lib/kubelet/config.yaml; systemctl restart kubelet" \
        >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------------------
# A previous attempt's answer must not survive into this one, and it could have
# been left on any worker, in either directory. Delete by name, never by glob
# over the whole directory.
# ---------------------------------------------------------------------------
while IFS='=' read -r alias name; do
    [ -n "$alias" ] || continue
    [ "$alias" = "controlplane" ] && continue
    DIR=$(ssh $SSH_OPTS "$alias" \
        "awk '/^staticPodPath:/ {print \$2}' /var/lib/kubelet/config.yaml" 2>/dev/null | tr -d '\r')
    [ -n "$DIR" ] || DIR=/etc/kubernetes/manifests
    ssh $SSH_OPTS "$alias" \
        "rm -f ${DIR}/${POD_BASE}.yaml ${DIR}/${POD_BASE}.yml ${DIR}/${POD_BASE}.json /etc/kubernetes/manifests/${POD_BASE}.yaml /etc/kubernetes/manifests/${POD_BASE}.yml" \
        >/dev/null 2>&1 || true
done < /tmp/exam/nodes.env

# ...and neither must a Pod the candidate created through the API server.
kubectl delete pod -n "$NAMESPACE" --all --ignore-not-found=true --timeout=60s >/dev/null 2>&1 || true

echo "Setup completed for Question 1"
