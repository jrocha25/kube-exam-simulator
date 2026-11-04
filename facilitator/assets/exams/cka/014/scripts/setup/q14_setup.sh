#!/bin/bash
set -e

# Question 14: CRDs of one API group among CRDs of others. The description of
# spec.retention carries a per-exam reference, so the explain output cannot be
# typed from memory.

WORKDIR=/tmp/exam/q14
mkdir -p "$WORKDIR"
rm -f "$WORKDIR"/*.txt

REF="RT-$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n' | tr 'a-f' 'A-F')"

crd() {
    local group=$1 kind=$2 plural=$3 extra=$4
    kubectl apply -f - <<YAML
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: ${plural}.${group}
spec:
  group: ${group}
  names:
    kind: ${kind}
    plural: ${plural}
    singular: $(echo "$kind" | tr 'A-Z' 'a-z')
  scope: Namespaced
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
${extra}
              station:
                type: string
                description: Tide station the object belongs to.
YAML
}

RETENTION=$(cat <<YAML
              retention:
                type: object
                description: How long forecast samples are kept before compaction, under harbor policy ${REF}.
                properties:
                  days:
                    type: integer
                    description: Number of days a forecast sample is kept.
                  compact:
                    type: boolean
                    description: Whether expired samples are compacted instead of deleted.
YAML
)

crd tides.harbor.io TideForecast tideforecasts "$RETENTION"
crd tides.harbor.io TideGauge tidegauges ""
crd tides.harbor.io TideAlert tidealerts ""
crd tides-archive.harbor.io TideSnapshot tidesnapshots ""
crd cranes.harbor.io CraneLift cranelifts ""

echo "Setup for question 14 completed"
