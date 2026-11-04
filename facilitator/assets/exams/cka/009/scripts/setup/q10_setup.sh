#!/bin/bash

set -e

# Question 10: two topologySpreadConstraints in one workload, contrasting the
# hard and soft forms of whenUnsatisfiable.
#
# The zone layout from q0 is 2 nodes in edge-1 and 1 in edge-2. With 4 replicas
# and maxSkew 1 on the zone key, DoNotSchedule forces a 2/2 split -- 3/1 has a
# skew of 2 and is refused. An even zone layout would have made a zone spread and
# a hostname spread indistinguishable, which is why q0 builds an uneven one.

NAMESPACE="sched-spread"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment --all -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true

echo "Setup completed for Question 10"
