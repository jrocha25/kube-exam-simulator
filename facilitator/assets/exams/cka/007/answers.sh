#!/bin/bash
# answers.md converted to answers.sh for quick testing of the cka-007 lab.
# Run it on the exam jumphost with KUBECONFIG pointing at the exam cluster.
set -x

### Question 1 -- a grant restricted to two named objects
kubectl create serviceaccount report-reader -n rbac-report

kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: config-reader
  namespace: rbac-report
rules:
- apiGroups: [""]
  resources: ["configmaps"]
  resourceNames: ["app-settings", "feature-flags"]
  verbs: ["get"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
EOF

kubectl create rolebinding report-reader-binding -n rbac-report \
  --role=config-reader --serviceaccount=rbac-report:report-reader

### Question 2 -- granting to a group and a user
kubectl create clusterrole infra-auditor \
  --verb=get,list,watch \
  --resource=nodes,persistentvolumes,namespaces,storageclasses.storage.k8s.io

kubectl create clusterrolebinding infra-auditors \
  --clusterrole=infra-auditor --group=platform-auditors --user=dana

### Question 3 -- an aggregated ClusterRole
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-view
aggregationRule:
  clusterRoleSelectors:
  - matchLabels:
      rbac.ck-x.io/aggregate-to-monitoring: "true"
rules: []
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-pods
  labels:
    rbac.ck-x.io/aggregate-to-monitoring: "true"
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: monitoring-nodes
  labels:
    rbac.ck-x.io/aggregate-to-monitoring: "true"
rules:
- apiGroups: [""]
  resources: ["nodes"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["nodes/metrics"]
  verbs: ["get"]
EOF

kubectl create serviceaccount dashboard -n rbac-monitor
kubectl create clusterrolebinding dashboard-monitoring \
  --clusterrole=monitoring-view --serviceaccount=rbac-monitor:dashboard

### Question 4 -- the scale subresource
kubectl create serviceaccount release-bot -n rbac-deploy

kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: scaler
  namespace: rbac-deploy
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list"]
- apiGroups: ["apps"]
  resources: ["deployments/scale"]
  verbs: ["get", "patch", "update"]
EOF

kubectl create rolebinding release-bot-scaler -n rbac-deploy \
  --role=scaler --serviceaccount=rbac-deploy:release-bot

### Question 5 -- tokens, and who gets one
kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: job-runner
  namespace: rbac-token
automountServiceAccountToken: false
---
apiVersion: v1
kind: Pod
metadata:
  name: probe
  namespace: rbac-token
spec:
  serviceAccountName: job-runner
  automountServiceAccountToken: true
  containers:
  - name: probe
    image: busybox:1.36
    command: ["sleep", "3600"]
EOF

mkdir -p /tmp/exam/q5
kubectl create token job-runner -n rbac-token > /tmp/exam/q5/token.jwt

### Question 6 -- documenting an authorization estate
mkdir -p /tmp/exam/q6

kubectl get rolebinding -n rbac-review \
  -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.roleRef.kind}{"/"}{.roleRef.name}{"\n"}{end}' \
  | sort > /tmp/exam/q6/bindings.txt

kubectl get rolebinding legacy-access -n rbac-review \
  -o jsonpath='{range .subjects[*]}{.kind}{"/"}{.name}{"\n"}{end}' \
  | sort > /tmp/exam/q6/subjects.txt

### Question 7 -- non-resource URLs
kubectl create serviceaccount probe-agent -n rbac-probe

kubectl create clusterrole endpoint-prober --verb=get \
  --non-resource-url=/healthz \
  --non-resource-url='/healthz/*' \
  --non-resource-url=/livez \
  --non-resource-url=/version \
  --non-resource-url=/metrics

kubectl create clusterrolebinding probe-agent-endpoints \
  --clusterrole=endpoint-prober --serviceaccount=rbac-probe:probe-agent

### Question 8 -- a grant nothing is using
kubectl set serviceaccount deployment/inventory-sync inventory-sync -n rbac-identity
kubectl rollout status deployment/inventory-sync -n rbac-identity --timeout=120s

### Question 9 -- rules pointing at the wrong API group
kubectl apply -f - <<'EOF'
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: job-manager
  namespace: rbac-jobs
rules:
- apiGroups: ["batch"]
  resources: ["cronjobs"]
  verbs: ["get", "list", "create"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
EOF

### Question 10 -- walking back an over-broad grant
kubectl delete clusterrolebinding backup-agent-admin

kubectl create role backup-reader -n rbac-excess \
  --verb=get,list --resource=pods,persistentvolumeclaims
kubectl create rolebinding backup-agent-reader -n rbac-excess \
  --role=backup-reader --serviceaccount=rbac-excess:backup-agent

kubectl create clusterrole backup-pv-reader \
  --verb=get,list --resource=persistentvolumes
kubectl create clusterrolebinding backup-agent-pv-reader \
  --clusterrole=backup-pv-reader --serviceaccount=rbac-excess:backup-agent
