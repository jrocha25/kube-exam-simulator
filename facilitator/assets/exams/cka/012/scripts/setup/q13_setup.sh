#!/bin/bash
set -e

# Question 13: two files, graded on what they contain rather than on how they
# were produced. Both expected values are recomputed from the live cluster at
# validation time, so neither can be typed from memory -- the node names are
# kind's, and the namespace count moves with the lab.

NAMESPACE="query-observatory"
DIR="/tmp/exam/q13"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

mkdir -p "$DIR"
rm -f "${DIR}/ready-nodes.txt" "${DIR}/ns-count.txt"

echo "Setup completed for Question 13"
