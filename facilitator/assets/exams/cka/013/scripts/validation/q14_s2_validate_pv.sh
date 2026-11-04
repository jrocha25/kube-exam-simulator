#!/bin/bash
set -e

PV="vault-pv-01"
LABEL_KEY="storage.ck-x.io/vault"

JSON=$(kubectl get pv "$PV" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ PersistentVolume '$PV' not found"
    exit 1
fi

if [[ "$(echo "$JSON" | jq -r '.spec.local.path // empty')" != "/srv/ck-x/tidevault" ]]; then
    echo "❌ '$PV' is not a local volume for /srv/ck-x/tidevault"
    exit 1
fi

GOT=$(echo "$JSON" | jq -c '{capacity: .spec.capacity.storage, modes: .spec.accessModes, class: .spec.storageClassName}')
if [[ "$GOT" != '{"capacity":"1Gi","modes":["ReadWriteOnce"],"class":"vault-local"}' ]]; then
    echo "❌ '$PV' is $GOT, expected 1Gi, ReadWriteOnce, class vault-local"
    exit 1
fi

KEYS=$(echo "$JSON" | jq -c '[.spec.nodeAffinity.required.nodeSelectorTerms[]?.matchExpressions[]?.key] | unique')
if [[ "$KEYS" != "[\"$LABEL_KEY\"]" ]]; then
    echo "❌ '$PV' node affinity uses $KEYS; it must use only $LABEL_KEY"
    exit 1
fi

echo "✅ '$PV' is a local volume pinned through $LABEL_KEY"
exit 0
