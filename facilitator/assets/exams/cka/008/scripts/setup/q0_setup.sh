#!/bin/bash

set -e

# Shared preamble. Setup scripts are picked up by the plain glob "q*_setup.sh" in
# jumphost/scripts/prepare-exam-env.sh, so this file runs first (glob order is
# q0, q1, q10..q12, q2..q9) even though no question maps to it.
#
# Nearly every question in this lab is graded by live traffic, which means an
# unenforced cluster does not fail loudly -- it fails silently, passing every
# "can reach" check and failing every "cannot reach" check no matter what the
# candidate wrote. On the kind flavour cka/006 can look for the calico-node
# DaemonSet, but k3s embeds its NetworkPolicy controller in the server process
# and exposes no object to look for. So the probe here has to be functional:
# stand up a client and a server, deny everything, and confirm the client is
# actually cut off.

mkdir -p /tmp/exam

PROBE_NS="np-probe"

kubectl delete namespace "$PROBE_NS" --ignore-not-found=true --timeout=60s &> /dev/null || true
kubectl create namespace "$PROBE_NS" --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: probe-server
  namespace: ${PROBE_NS}
  labels:
    app: probe-server
spec:
  containers:
  - name: web
    image: nginx:1.27.4
    ports:
    - containerPort: 80
---
apiVersion: v1
kind: Pod
metadata:
  name: probe-client
  namespace: ${PROBE_NS}
spec:
  containers:
  - name: shell
    image: busybox:1.36
    command: ["sh", "-c", "sleep 86400"]
YAML

kubectl wait --for=condition=Ready pod/probe-server pod/probe-client -n "$PROBE_NS" --timeout=120s || true

kubectl apply -f - <<YAML
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: probe-deny-all
  namespace: ${PROBE_NS}
spec:
  podSelector: {}
  policyTypes:
  - Ingress
YAML

SERVER_IP=$(kubectl get pod probe-server -n "$PROBE_NS" -o jsonpath='{.status.podIP}' 2> /dev/null || true)

ENFORCED="unknown"
if [[ -n "$SERVER_IP" ]]; then
    # Give the controller a moment to program the rule, then check that the
    # client is genuinely blocked. Bounded to ~25s: this runs before every
    # attempt and the candidate pays for it in warm-up time.
    for _ in $(seq 1 5); do
        if kubectl exec probe-client -n "$PROBE_NS" --request-timeout=30s -- \
                wget -q -T 3 -t 1 -O- "http://${SERVER_IP}:80" &> /dev/null; then
            ENFORCED="no"
        else
            ENFORCED="yes"
            break
        fi
        sleep 5
    done
fi

if [[ "$ENFORCED" != "yes" ]]; then
    echo "unavailable" > /tmp/exam/networkpolicy-unavailable
    echo "WARNING: NetworkPolicy is not being enforced on this cluster."
    echo "WARNING: every question in this lab is graded by live traffic, so scores will be meaningless."
    echo "WARNING: the k3d cluster image ships the k3s NetworkPolicy controller; rebuild it with:"
    echo "WARNING:   ./start.sh --stop && ./start.sh --rebuild"
else
    rm -f /tmp/exam/networkpolicy-unavailable
fi

kubectl delete namespace "$PROBE_NS" --ignore-not-found=true --wait=false &> /dev/null || true

echo "Shared setup completed (NetworkPolicy enforcement: ${ENFORCED})"
