#!/bin/bash
set -e

# Question 1: manual PersistentVolume / PersistentVolumeClaim / Pod
kubectl create namespace storage-manual --dry-run=client -o yaml | kubectl apply -f -

# Remove any leftover objects the candidate is expected to create
kubectl delete pod log-writer -n storage-manual --ignore-not-found=true
kubectl delete pvc logs-pvc -n storage-manual --ignore-not-found=true
kubectl delete pv logs-pv --ignore-not-found=true

echo "Setup completed for Question 1"
