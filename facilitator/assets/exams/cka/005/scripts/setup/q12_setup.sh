#!/bin/bash
set -e

# Question 12: the candidate adds a public chart repository and drives a release
# through an upgrade. Nothing is pre-created beyond the namespace -- but any
# leftovers from a previous attempt are cleared so "helm install" is not met with
# an existing release.
kubectl create namespace helm-pub --dry-run=client -o yaml | kubectl apply -f -

helm uninstall podinfo -n helm-pub 2>/dev/null || true
helm repo remove podinfo 2>/dev/null || true

echo "Setup completed for Question 12"
