#!/bin/bash
set -e

# Question 15: an overlay whose two patches both name a Deployment that does not
# exist in the base, so kustomize refuses to build anything at all.
kubectl create namespace kustom-fix --dry-run=client -o yaml | kubectl apply -f -

kubectl delete deployment,service --all -n kustom-fix --ignore-not-found=true

rm -rf /tmp/exam/q15
mkdir -p /tmp/exam/q15/base /tmp/exam/q15/overlays/staging

cat > /tmp/exam/q15/base/deployment.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api
  template:
    metadata:
      labels:
        app: api
    spec:
      containers:
      - name: api
        image: nginx:1.25
        ports:
        - containerPort: 80
YAML

cat > /tmp/exam/q15/base/service.yaml <<'YAML'
apiVersion: v1
kind: Service
metadata:
  name: api
spec:
  type: ClusterIP
  selector:
    app: api
  ports:
  - protocol: TCP
    port: 80
    targetPort: 80
YAML

cat > /tmp/exam/q15/base/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
- deployment.yaml
- service.yaml
YAML

cat > /tmp/exam/q15/overlays/staging/replicas-patch.yaml <<'YAML'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
spec:
  replicas: 5
YAML

cat > /tmp/exam/q15/overlays/staging/image-patch.yaml <<'YAML'
- op: replace
  path: /spec/template/spec/containers/0/image
  value: nginx:1.27.4
YAML

cat > /tmp/exam/q15/overlays/staging/kustomization.yaml <<'YAML'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: kustom-fix
resources:
- ../../base
patches:
- path: replicas-patch.yaml
- path: image-patch.yaml
  target:
    kind: Deployment
    name: api-server
YAML

# Recorded so the validation can tell a fixed overlay from a rewritten base --
# the base is meant to be shared and off limits.
( cd /tmp/exam/q15 && sha256sum base/* > /tmp/exam/q15/base.sha256 )

echo "Setup completed for Question 15"
