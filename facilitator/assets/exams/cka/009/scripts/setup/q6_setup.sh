#!/bin/bash

set -e

# Question 6: required node affinity where one matchExpression is not enough.
#
# q0 labels the three nodes:  general (server), compute (agent-0),
# memory + decommission=pending (agent-1). So "node-class in (compute, memory)"
# alone matches two nodes, one of which is on its way out; adding the negative
# expression to the SAME nodeSelectorTerm narrows it to exactly one. That single
# eligible node is what makes the placement check unambiguous, and it is what
# fails an answer pasted from the documentation's single-expression example.
#
# Nothing to seed but the namespace -- the candidate writes the whole workload.

NAMESPACE="sched-nodeaff"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment --all -n "$NAMESPACE" --ignore-not-found=true --timeout=60s || true

echo "Setup completed for Question 6"
