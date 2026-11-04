#!/bin/bash
set -e

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

JSON=$(kubectl get tidegauge gauge-03 -n ts-decom-keep -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ gauge-03 in ts-decom-keep was deleted"
    exit 1
fi
if [[ "$(echo "$JSON" | jq -r '.metadata.uid')" != "$(cat /tmp/exam/q16/gauge-03.uid 2>/dev/null)" ]]; then
    echo "❌ gauge-03 in ts-decom-keep was replaced"
    exit 1
fi
if [[ "$(echo "$JSON" | jq -r '.metadata.deletionTimestamp // empty')" != "" ]]; then
    echo "❌ gauge-03 in ts-decom-keep is being deleted"
    exit 1
fi
if [[ "$(echo "$JSON" | jq -c '.metadata.finalizers')" != '["ops.ck-x.io/drain-hook"]' ]]; then
    echo "❌ gauge-03 in ts-decom-keep lost its finalizer"
    exit 1
fi

echo "✅ gauge-03 in ts-decom-keep is untouched"
exit 0
