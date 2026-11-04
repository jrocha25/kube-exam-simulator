#!/bin/bash
set -e

# Question 2: dynamic provisioning with a custom StorageClass
kubectl create namespace storage-dynamic --dry-run=client -o yaml | kubectl apply -f -

# Remove any leftover objects the candidate is expected to create
kubectl delete pod archiver -n storage-dynamic --ignore-not-found=true
kubectl delete pvc archive-pvc -n storage-dynamic --ignore-not-found=true
kubectl delete storageclass retain-local --ignore-not-found=true

echo "Setup completed for Question 2"
