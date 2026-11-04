#!/bin/bash
set -e

# Question 14: a StorageClass, a claim and a Pod. Only the namespace is staged;
# a StorageClass from a previous attempt is removed so that what is graded is
# what the candidate wrote. The provisioner the question names is kind's
# local-path provisioner, which honours any StorageClass that points at it.

NAMESPACE="stor-bulk"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete pod bulk-writer -n "$NAMESPACE" --ignore-not-found=true --wait=false
kubectl delete pvc bulk-data -n "$NAMESPACE" --ignore-not-found=true --wait=false
kubectl delete storageclass bulk-retain --ignore-not-found=true

echo "Setup completed for Question 14"
