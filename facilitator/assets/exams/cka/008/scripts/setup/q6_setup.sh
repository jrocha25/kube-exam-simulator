#!/bin/bash

set -e

# Question 6: ipBlock, graded on the policy spec rather than by live traffic.
# Egress to the public internet is not something this cluster can be relied on
# to have, and 169.254.169.254 is not routable here at all, so reachability
# would prove nothing either way. Only one Pod is needed.
#
# The question names 10.42.0.0/16 as the cluster Pod network. That is the k3s
# default and this lab pins clusterType to k3d, but check it anyway: if the
# flavour ever changes underneath us the question becomes wrong, and a warning
# in the setup log is how that gets noticed.

NAMESPACE="np-external"
EXPECTED_POD_CIDR="10.42."

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl delete networkpolicy --all -n "$NAMESPACE" --ignore-not-found=true || true
kubectl delete pod gateway -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true

kubectl apply -f - <<YAML
apiVersion: v1
kind: Pod
metadata:
  name: gateway
  namespace: ${NAMESPACE}
  labels:
    app: gateway
spec:
  containers:
  - name: web
    image: nginx:1.27.4
    ports:
    - containerPort: 80
YAML

kubectl wait --for=condition=Ready pod/gateway -n "$NAMESPACE" --timeout=120s || true

NODE_CIDR=$(kubectl get nodes -o jsonpath='{.items[0].spec.podCIDR}' 2> /dev/null || true)
if [[ -n "$NODE_CIDR" && "$NODE_CIDR" != ${EXPECTED_POD_CIDR}* ]]; then
    echo "WARNING: this cluster allocates Pod IPs from '${NODE_CIDR}', but question 6 names 10.42.0.0/16."
    echo "WARNING: the question text and q6_s2_validate_except.sh both need updating."
fi

echo "Setup completed for Question 6"
