#!/bin/bash
set -e

# Question 4: CronJob plus a manually triggered Job
kubectl create namespace batch-jobs --dry-run=client -o yaml | kubectl apply -f -

kubectl delete job db-backup-manual -n batch-jobs --ignore-not-found=true
kubectl delete cronjob db-backup -n batch-jobs --ignore-not-found=true

echo "Setup completed for Question 4"
