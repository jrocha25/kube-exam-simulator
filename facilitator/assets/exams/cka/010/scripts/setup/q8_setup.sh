#!/bin/bash
set -e

# Question 8: a CRD from scratch. Only the namespace the instance goes in is
# staged; a CRD a previous attempt left behind is removed so that the schema
# the candidate writes is the one graded.

NAMESPACE="crd-freight"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete crd shipments.logistics.ck-x.io --ignore-not-found=true

echo "Setup completed for Question 8"
