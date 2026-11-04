#!/bin/bash
set -e

# Question 6: runs that overlap and never finish.
#
# Two faults, both at a different level of the object: concurrencyPolicy on the
# CronJob spec is Allow, and the Job template spec has no activeDeadlineSeconds,
# so a container that sleeps for 150 seconds on a one-minute schedule stacks up
# two or three runs at a time within a few minutes.
#
# The sleep is 150s rather than something longer so that the symptom appears
# while the candidate is still in the exam, and so that an unfixed CronJob never
# holds more than three Pods at once.

NAMESPACE="wl-rotate"
CRONJOB="digest-trim"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Start from the broken state on every warm-up, and take the piled-up Jobs of a
# previous attempt with it.
kubectl delete cronjob "$CRONJOB" -n "$NAMESPACE" --ignore-not-found=true >/dev/null 2>&1 || true
kubectl delete job --all -n "$NAMESPACE" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true

kubectl apply -f - <<'YAML'
apiVersion: batch/v1
kind: CronJob
metadata:
  name: digest-trim
  namespace: wl-rotate
spec:
  schedule: "*/1 * * * *"
  concurrencyPolicy: Allow
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: trim
            image: busybox:1.36
            command: ["sh", "-c", "echo trimming digest && sleep 150"]
          restartPolicy: OnFailure
YAML

echo "Setup completed for Question 6"
