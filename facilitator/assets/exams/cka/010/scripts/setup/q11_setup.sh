#!/bin/bash
set -e

# Question 11: a CronJob and a Job created from it. Only the namespace is
# staged; leftovers from a previous attempt are removed so the manual Job the
# candidate creates is the one graded.

NAMESPACE="batch-reports"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete cronjob report-sweeper -n "$NAMESPACE" --ignore-not-found=true
kubectl delete job report-sweeper-manual -n "$NAMESPACE" --ignore-not-found=true

echo "Setup completed for Question 11"
