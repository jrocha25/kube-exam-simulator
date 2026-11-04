#!/bin/bash
set -e

# Question 1: upgrade the auxiliary cluster from 1.33.12 to 1.34.10 with kubeadm.
#
# The cluster itself is already the old minor -- config.json's "auxNodeImage"
# built it on kindest/node:v1.33.12 -- so what this script stages is the *package*
# state the real exam starts from. kindest/node ships kubeadm, kubelet and kubectl
# as bare binaries in /usr/bin with no apt repository behind them; the exam's
# procedure is "change the repo to the next minor, apt-mark unhold, apt-get
# install kubeadm=..., kubeadm upgrade apply, same for the kubelet". So:
#
#   * configure the pkgs.k8s.io repository for the CURRENT minor (v1.33),
#     exactly as the kubeadm install docs do -- keyring, sources.list.d entry
#   * install the 1.33.12 debs over the identical 1.33.12 binaries, which
#     changes nothing on disk but puts the three under dpkg's control
#   * hold them, the way the docs tell an operator to leave them
#
# The kubelet deb ships /etc/default/kubelet as a conffile and kind's node image
# already has one (it sets --runtime-cgroups), so dpkg would stop at an
# interactive conffile prompt without --force-confold. Keeping kind's copy is
# also what a later upgrade does automatically: dpkg only prompts when both the
# local file and the package's version changed, and the package's has not.
#
# The 1.34.10 control-plane images are pre-pulled in the background as a favour
# to the candidate: kubeadm upgrade apply spends most of its three minutes
# pulling them, and nothing about the procedure depends on the pull being slow.

AUX_KUBECONFIG=/home/candidate/.kube/kubeconfig-aux
CURRENT_MINOR="v1.33"
CURRENT_DEB="1.33.12-1.1"
TARGET_VERSION="v1.34.10"
# What kubeadm 1.34.10 will want to pull. From "kubeadm config images list"
# for that version; a mismatch only costs the pre-pull, never the question.
PREPULL_IMAGES="registry.k8s.io/kube-apiserver:${TARGET_VERSION} \
registry.k8s.io/kube-controller-manager:${TARGET_VERSION} \
registry.k8s.io/kube-scheduler:${TARGET_VERSION} \
registry.k8s.io/kube-proxy:${TARGET_VERSION} \
registry.k8s.io/etcd:3.6.5-0 \
registry.k8s.io/coredns/coredns:v1.12.1"

if [ -f /tmp/exam/aux-cluster-unavailable ]; then
    echo "WARNING: the auxiliary cluster is unavailable, skipping question 1 setup."
    echo "WARNING: see the warning from q0_setup.sh for the fix."
    exit 0
fi
if [ -f /tmp/exam/aux-version-unexpected ]; then
    echo "WARNING: the auxiliary cluster is not on ${CURRENT_MINOR}, skipping question 1 setup."
    echo "WARNING: installing ${CURRENT_DEB} over it would downgrade a running kubelet."
    exit 0
fi

export KUBECONFIG="$AUX_KUBECONFIG"
kubectl create namespace upgrade-aux --dry-run=client -o yaml | kubectl apply -f -

# Belt and braces: q0 read the version through the API, this reads the binary
# the packages are about to be installed over.
NODE_KUBEADM=$(ssh -o ConnectTimeout=10 aux "kubeadm version -o short" 2>/dev/null || true)
if [ "$NODE_KUBEADM" != "${CURRENT_DEB%%-*}" ] && [ "$NODE_KUBEADM" != "v${CURRENT_DEB%%-*}" ]; then
    echo "WARNING: kubeadm on the aux node is '${NODE_KUBEADM}', expected v${CURRENT_DEB%%-*}."
    echo "WARNING: skipping question 1 setup rather than installing a different version."
    exit 0
fi

ssh -o ConnectTimeout=10 aux "CURRENT_MINOR=${CURRENT_MINOR} CURRENT_DEB=${CURRENT_DEB} bash -s" <<'REMOTE'
set -e
export DEBIAN_FRONTEND=noninteractive

if apt-mark showhold 2>/dev/null | grep -qx kubeadm \
        && [ "$(dpkg-query -W -f='${Version}' kubeadm 2>/dev/null)" = "$CURRENT_DEB" ]; then
    echo "kubeadm ${CURRENT_DEB} is already installed and held; nothing to stage"
    exit 0
fi

apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq apt-transport-https ca-certificates curl gnupg >/dev/null 2>&1

mkdir -p -m 755 /etc/apt/keyrings
rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
curl -fsSL "https://pkgs.k8s.io/core:/stable:/${CURRENT_MINOR}/deb/Release.key" \
    | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/${CURRENT_MINOR}/deb/ /" \
    > /etc/apt/sources.list.d/kubernetes.list
apt-get update -qq >/dev/null 2>&1

apt-mark unhold kubeadm kubelet kubectl >/dev/null 2>&1 || true
apt-get install -y -qq -o Dpkg::Options::=--force-confold \
    "kubeadm=${CURRENT_DEB}" "kubelet=${CURRENT_DEB}" "kubectl=${CURRENT_DEB}" >/dev/null 2>&1
apt-mark hold kubeadm kubelet kubectl

echo "packages: $(dpkg-query -W -f='${Package}=${Version} ' kubeadm kubelet kubectl)"
echo "held: $(apt-mark showhold | tr '\n' ' ')"
systemctl is-active kubelet >/dev/null || echo "WARNING: the kubelet is not active after the package install"
REMOTE

# Pre-pull, detached from this SSH session so setup does not wait on it.
ssh -o ConnectTimeout=10 aux "PREPULL_IMAGES='${PREPULL_IMAGES}' bash -s" <<'REMOTE'
setsid nohup bash -c '
    for img in $PREPULL_IMAGES; do
        crictl pull "$img" >/dev/null 2>&1 || echo "pre-pull of $img failed"
    done
    echo "pre-pull finished"
' > /var/log/ck-x-prepull.log 2>&1 < /dev/null &
echo "pre-pull of the ${TARGET_VERSION:-1.34.10} control-plane images started in the background"
REMOTE

echo "Setup completed for Question 1 (auxiliary cluster is on ${CURRENT_DEB%%-*}, packages held)"
