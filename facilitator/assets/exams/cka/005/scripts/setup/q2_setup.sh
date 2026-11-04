#!/bin/bash
set -e

# Question 2: the candidate builds the StorageClass, claim and Pod from scratch.
kubectl create namespace store-tier --dry-run=client -o yaml | kubectl apply -f -

kubectl delete pod archive-writer -n store-tier --ignore-not-found=true --timeout=60s || true
kubectl delete pvc archive-claim -n store-tier --ignore-not-found=true --timeout=60s || true
kubectl delete storageclass slow-retain --ignore-not-found=true

echo "Setup completed for Question 2"
