#!/bin/bash
set -e

# Question 16: a namespace stuck Terminating behind custom resources whose
# finalizer's controller is gone. The honest fix is to remove the finalizer from
# the resources still in ts-decom; the namespace then finishes on its own.
#
# The tempting shortcut -- PUT the namespace to /finalize with an empty list --
# makes the namespace disappear but leaves its resources in etcd, still listable
# with "kubectl get tidegauges -n ts-decom". That is what step 1 checks for.
# gauge-03 in a sibling namespace carries the same finalizer and must survive:
# a candidate who strips the finalizer cluster-wide, or deletes the CRD, breaks it.

CRD="tidegauges.ops.ck-x.io"
STATE_DIR=/tmp/exam/q16

mkdir -p "$STATE_DIR"

kubectl apply -f - <<'YAML'
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: tidegauges.ops.ck-x.io
spec:
  group: ops.ck-x.io
  scope: Namespaced
  names:
    plural: tidegauges
    singular: tidegauge
    kind: TideGauge
    shortNames: ["tg"]
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
              station: {type: string}
              intervalSeconds: {type: integer}
YAML
kubectl wait --for=condition=Established crd/"$CRD" --timeout=60s >/dev/null \
    || echo "WARNING: the TideGauge CRD did not become established"

for ns in ts-decom ts-decom-keep; do
    kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null 2>&1 \
        || echo "WARNING: namespace $ns could not be created (still terminating from an earlier run?)"
done

kubectl apply -f - <<'YAML'
apiVersion: ops.ck-x.io/v1
kind: TideGauge
metadata:
  name: gauge-17
  namespace: ts-decom
  finalizers: ["ops.ck-x.io/drain-hook"]
spec:
  station: north-mole
  intervalSeconds: 60
---
apiVersion: ops.ck-x.io/v1
kind: TideGauge
metadata:
  name: gauge-21
  namespace: ts-decom
  finalizers: ["ops.ck-x.io/drain-hook"]
spec:
  station: east-quay
  intervalSeconds: 30
---
apiVersion: ops.ck-x.io/v1
kind: TideGauge
metadata:
  name: gauge-03
  namespace: ts-decom-keep
  finalizers: ["ops.ck-x.io/drain-hook"]
spec:
  station: harbour-mouth
  intervalSeconds: 60
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: gauge-calibration
  namespace: ts-decom
data:
  offset-cm: "12"
YAML

kubectl get crd "$CRD" -o jsonpath='{.metadata.uid}' > "$STATE_DIR/crd.uid"
kubectl get tidegauge gauge-03 -n ts-decom-keep -o jsonpath='{.metadata.uid}' > "$STATE_DIR/gauge-03.uid"

kubectl delete namespace ts-decom --wait=false

STUCK=no
for _ in $(seq 1 12); do
    if kubectl get namespace ts-decom -o jsonpath='{.status.conditions[?(@.type=="NamespaceFinalizersRemaining")].status}' 2>/dev/null | grep -q True; then
        STUCK=yes
        break
    fi
    sleep 5
done
[ "$STUCK" = yes ] || echo "WARNING: ts-decom is not waiting on finalizers yet"

echo "Setup completed for Question 16"
