#!/bin/bash
exec >> /proc/1/fd/1 2>&1


# Log function with timestamp
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

# Set defaults
NUMBER_OF_NODES=${1:-1}
EXAM_ID=${2:-""}
# Cluster flavour, from "clusterType" in the lab's config.json. Labs that predate
# the split send nothing, so the default has to stay k3d.
CLUSTER_TYPE=${3:-k3d}
# Optional auxiliary cluster, from "auxCluster" in the lab's config.json. Empty for
# every lab that does not ask for one, which is all of them but cka-006.
AUX_CLUSTER_TYPE=${4:-""}
# Optional kind node image for the auxiliary cluster, from "auxNodeImage" in the
# lab's config.json. Lets the aux cluster start one Kubernetes minor behind the
# image pinned in the cluster image, so a question can upgrade it with kubeadm.
# Empty for every lab that does not ask for one.
AUX_NODE_IMAGE=${5:-""}

# CLUSTER_NAME comes from the image's ENV, which sshd does NOT hand to a session --
# and this script is invoked over SSH by the facilitator. It has always been empty
# here; that went unnoticed while it was the last argument, because env-setup's own
# ${2:-cluster} default covered it. It is not the last argument any more, so an
# empty value would shift CLUSTER_TYPE into the name slot. Default it explicitly.
CLUSTER_NAME=${CLUSTER_NAME:-cluster}

AUX_CLUSTER_NAME="${CLUSTER_NAME}-aux"
AUX_KUBECONFIG=/home/candidate/.kube/kubeconfig-aux

echo "Exam ID: $EXAM_ID"
echo "Number of nodes: $NUMBER_OF_NODES"
echo "Cluster type: $CLUSTER_TYPE"
echo "Auxiliary cluster: ${AUX_CLUSTER_TYPE:-none}"
echo "Auxiliary cluster node image: ${AUX_NODE_IMAGE:-default}"

#check docker is running
if ! docker info > /dev/null 2>&1; then
  log "Docker is not running"
  log "Attempting to start docker"
  dockerd &
  sleep 5
  #check docker is running 3 times with 5 second interval
  for i in {1..3}; do
    if docker info > /dev/null 2>&1; then
      log "Docker started successfully"
      break
    fi
    log "Docker failed to start, retrying..."
    sleep 5
  done
fi

log "Starting exam environment preparation with $NUMBER_OF_NODES node(s)"

# Validate input
if ! [[ "$NUMBER_OF_NODES" =~ ^[0-9]+$ ]]; then
  log "ERROR: Number of nodes must be a positive integer"
  exit 1
fi

# Both of these are interpolated into a command run over SSH. examService.js already
# matches them against an allowlist; check again here rather than trusting that one
# caller, since this script is reachable on its own.
if ! [[ "$CLUSTER_TYPE" =~ ^(k3d|kind)$ ]]; then
  log "ERROR: Unsupported cluster type '$CLUSTER_TYPE'"
  exit 1
fi
if [[ -n "$AUX_CLUSTER_TYPE" ]] && ! [[ "$AUX_CLUSTER_TYPE" =~ ^kind$ ]]; then
  log "WARNING: Unsupported auxiliary cluster type '$AUX_CLUSTER_TYPE', ignoring it"
  AUX_CLUSTER_TYPE=""
fi
# An image reference is not an enum, so this one is matched against the exact
# shape of a kindest/node reference instead -- the same pattern examService.js uses.
if [[ -n "$AUX_NODE_IMAGE" ]] && ! [[ "$AUX_NODE_IMAGE" =~ ^kindest/node:v[0-9]+\.[0-9]+\.[0-9]+(@sha256:[0-9a-f]{64})?$ ]]; then
  log "WARNING: Rejected auxiliary node image '$AUX_NODE_IMAGE', using the default"
  AUX_NODE_IMAGE=""
fi

# The auxiliary cluster's SSH connection is now the first one made to
# k8s-api-server, where the primary's used to be. A single-shot ssh against an sshd
# that has not finished starting fails immediately, and for the aux cluster that
# would cost a question rather than the exam -- quietly. Wait for the port, bounded;
# this is a no-op once sshd is up, which it normally already is.
for _ in $(seq 1 12); do
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 \
      candidate@k8s-api-server true > /dev/null 2>&1 && break
  log "k8s-api-server is not accepting SSH yet, retrying..."
  sleep 5
done

# ---------------------------------------------------------------------------
# Auxiliary cluster
#
# Started first and in the background so its kubeadm bootstrap and Calico rollout
# overlap the primary cluster's rather than being added to the end of the warm-up.
# It is a single control-plane node, so it finishes well inside the time the
# primary takes.
#
# Nothing below may make preparation fail on its account: a missing aux cluster
# costs the questions that use it and must leave the rest of the lab gradeable,
# which is the same contract env-setup-kind keeps.
# ---------------------------------------------------------------------------
AUX_PID=""
if [[ -n "$AUX_CLUSTER_TYPE" ]]; then
  log "Starting auxiliary cluster '$AUX_CLUSTER_NAME' ($AUX_CLUSTER_TYPE) in the background"
  ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null candidate@k8s-api-server \
    "env-setup 0 $AUX_CLUSTER_NAME $AUX_CLUSTER_TYPE aux $AUX_NODE_IMAGE" &
  AUX_PID=$!
fi

# Setup the exam cluster
ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null candidate@k8s-api-server "env-setup $NUMBER_OF_NODES $CLUSTER_NAME $CLUSTER_TYPE"

#Pull assets from URL
curl facilitator:3000/api/v1/exams/$EXAM_ID/assets -o assets.tar.gz

mkdir -p /tmp/exam-assets
#Unzip assets
tar -xzvf assets.tar.gz -C /tmp/exam-assets    

#Remove assets.tar.gz
rm assets.tar.gz

#make every file in /tmp/exam-assets executable
find /tmp/exam-assets -type f -exec chmod +x {} \;

echo "Exam assets downloaded and prepared successfully" 

export KUBECONFIG=/home/candidate/.kube/kubeconfig

sleep 5

#wait till api-server is ready
while ! kubectl get nodes > /dev/null 2>&1; do
  log "API server is not ready, retrying..."
  sleep 5
done

echo "API server is ready"

# ---------------------------------------------------------------------------
# Wait for the auxiliary cluster, if one was asked for.
#
# Bounded, unlike the primary loop above: a lab can be graded without its aux
# cluster, so an aux cluster that never arrives has to say so and let the setup
# scripts run rather than holding the warm-up open indefinitely.
# ---------------------------------------------------------------------------
if [[ -n "$AUX_PID" ]]; then
  log "Waiting for the auxiliary cluster to finish building..."
  wait "$AUX_PID" || log "WARNING: auxiliary cluster setup exited non-zero"

  AUX_READY=no
  for _ in $(seq 1 24); do
    if kubectl --kubeconfig="$AUX_KUBECONFIG" get nodes > /dev/null 2>&1; then
      AUX_READY=yes
      break
    fi
    sleep 5
  done

  if [[ "$AUX_READY" == "yes" ]]; then
    log "Auxiliary cluster is ready"
  else
    log "WARNING: the auxiliary cluster did not come up."
    log "WARNING: questions that use it cannot be answered; the rest of the lab"
    log "WARNING: is unaffected. Check the k8s-api-server logs for [aux] lines."
  fi
fi

#Run setup scripts
for script in /tmp/exam-assets/scripts/setup/q*_setup.sh; do $script; done

log "Exam environment preparation completed successfully"
exit 0 