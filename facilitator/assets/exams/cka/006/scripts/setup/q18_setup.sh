#!/bin/bash
set -e

# Question 18: priority and preemption. A low-priority workload is sized to fill
# the reserved node, so the high-priority one the candidate creates cannot be
# scheduled without evicting it. That only happens if the PriorityClasses carry
# the right values and preemptionPolicy is left at its default -- a candidate who
# sets preemptionPolicy: Never gets a permanently Pending pod.
#
# The filler is pinned to a single node with a nodeSelector so preemption has a
# bounded arena and cannot disturb the other questions' workloads.

NAMESPACE="sched-priority"

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl delete deployment --all -n "$NAMESPACE" --ignore-not-found=true
kubectl delete priorityclass batch-low critical-high --ignore-not-found=true

# Size the filler against what node03 actually offers, so this works whatever the
# host running the simulator happens to have.
ALLOC=$(kubectl get nodes -l ck-x.io/alias=node03 \
    -o jsonpath='{.items[0].status.allocatable.memory}' 2>/dev/null || echo "")
FILLER_MI=512
case "$ALLOC" in
    *Ki) FILLER_MI=$(( ${ALLOC%Ki} / 1024 / 3 )) ;;
esac
[ "$FILLER_MI" -lt 256 ] && FILLER_MI=256
echo "Filler pods will each request ${FILLER_MI}Mi"

kubectl apply -f - <<YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: bulk-import
  namespace: $NAMESPACE
spec:
  replicas: 3
  selector:
    matchLabels:
      app: bulk-import
  template:
    metadata:
      labels:
        app: bulk-import
    spec:
      nodeSelector:
        ck-x.io/alias: node03
      containers:
      - name: worker
        image: busybox:1.36
        command: ["sh", "-c", "sleep 86400"]
        resources:
          requests:
            memory: "${FILLER_MI}Mi"
YAML

echo "${FILLER_MI}" > /tmp/exam/q18-filler-mi

kubectl rollout status deployment/bulk-import -n "$NAMESPACE" --timeout=180s \
    || echo "WARNING: bulk-import did not become ready in time"

echo "Setup completed for Question 18"
