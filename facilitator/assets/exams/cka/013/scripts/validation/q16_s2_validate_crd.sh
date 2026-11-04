#!/bin/bash
set -e

CRD="tidegauges.ops.ck-x.io"

# A constraint: only counts once the namespace is gone the right way -- a
# force-finalized namespace leaves its TideGauges behind and earns nothing here.
if kubectl get namespace ts-decom >/dev/null 2>&1; then
    echo "❌ Namespace 'ts-decom' still exists"
    exit 1
fi
if [[ -n "$(kubectl get tidegauges.ops.ck-x.io -n ts-decom -o name 2>/dev/null)" ]]; then
    echo "❌ ts-decom's TideGauges were left behind"
    exit 1
fi

CRD_UID=$(kubectl get crd "$CRD" -o jsonpath='{.metadata.uid}' 2>/dev/null || true)
if [[ -z "$CRD_UID" || "$CRD_UID" != "$(cat /tmp/exam/q16/crd.uid 2>/dev/null)" ]]; then
    echo "❌ The CustomResourceDefinition '$CRD' was deleted or replaced"
    exit 1
fi

echo "✅ The CustomResourceDefinition '$CRD' is untouched"
exit 0
