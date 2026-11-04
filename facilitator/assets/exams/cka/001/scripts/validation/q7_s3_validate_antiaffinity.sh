#!/bin/bash
set -e

NAMESPACE="default"
DEPLOYMENT="web-app"
EXPECTED_REPLICAS=3
TOPOLOGY_KEY="kubernetes.io/hostname"

if ! kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Deployment '$DEPLOYMENT' not found in namespace '$NAMESPACE'"
    exit 1
fi

JSON=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json)

# The rule has to be a preference: this cluster has fewer nodes than replicas,
# so a required rule would leave a Pod permanently Pending.
PREFERRED=$(echo "$JSON" | jq '[.spec.template.spec.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[]?] | length')
if [[ "$PREFERRED" == "0" ]]; then
    REQUIRED=$(echo "$JSON" | jq '[.spec.template.spec.affinity.podAntiAffinity.requiredDuringSchedulingIgnoredDuringExecution[]?] | length')
    if [[ "$REQUIRED" != "0" ]]; then
        echo "❌ '$DEPLOYMENT' uses a required pod anti-affinity; the rule must be a preference"
        exit 1
    fi
    echo "❌ '$DEPLOYMENT' declares no pod anti-affinity rule"
    exit 1
fi

KEYS=$(echo "$JSON" | jq -r '[.spec.template.spec.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[]?.podAffinityTerm.topologyKey] | join(",")')
if [[ "$KEYS" != *"$TOPOLOGY_KEY"* ]]; then
    echo "❌ The anti-affinity rule uses topology key(s) '$KEYS', expected '$TOPOLOGY_KEY'"
    exit 1
fi

# A rule whose selector matches nothing spreads nothing, which is the usual slip.
SELECTOR_MATCHES=$(echo "$JSON" | jq -r '
    (.spec.selector.matchLabels // {}) as $own
    | [ .spec.template.spec.affinity.podAntiAffinity.preferredDuringSchedulingIgnoredDuringExecution[]?
        | .podAffinityTerm.labelSelector.matchLabels // {}
        | to_entries
        | select(length > 0)
        | all(.[]; $own[.key] == .value) ]
    | any')
if [[ "$SELECTOR_MATCHES" != "true" ]]; then
    echo "❌ The anti-affinity rule does not select the deployment's own Pods"
    exit 1
fi

for _ in $(seq 1 12); do
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o jsonpath='{.status.readyReplicas}')
    [[ "$READY" == "$EXPECTED_REPLICAS" ]] && break
    sleep 5
done

if [[ "$READY" != "$EXPECTED_REPLICAS" ]]; then
    echo "❌ '$DEPLOYMENT' has ${READY:-0}/$EXPECTED_REPLICAS ready replicas"
    exit 1
fi

echo "✅ '$DEPLOYMENT' prefers to spread its Pods by $TOPOLOGY_KEY and all $EXPECTED_REPLICAS replicas are ready"
exit 0
