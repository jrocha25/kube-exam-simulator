#!/bin/bash
set -e

# Question 11: CustomResourceDefinition and a custom resource
kubectl create namespace crd-lab --dry-run=client -o yaml | kubectl apply -f -

kubectl delete crd backupjobs.ops.example.com --ignore-not-found=true

rm -rf /tmp/exam/q11
mkdir -p /tmp/exam/q11

cat > /tmp/exam/q11/backupjob-crd.yaml <<'EOF'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: backupjobs.ops.example.com
spec:
  group: ops.example.com
  scope: Namespaced
  names:
    plural: backupjobs
    singular: backupjob
    kind: BackupJob
    shortNames:
    - bj
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              schedule:
                type: string
              retention:
                type: integer
EOF

echo "Setup completed for Question 11"
