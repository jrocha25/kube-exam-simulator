#!/bin/bash

set -e

# Whether a podSelector selects a Pod is decided by matchLabels being a subset of
# the Pod's labels (an empty selector matching everything), so compare the two
# label sets directly rather than round-tripping through 'kubectl -l', which
# cannot express every selector form.
#
# The Pod's own labels are checked too. Relabelling 'vault' would also make the
# policy bite, but it would break the Service selector that points at it, and the
# question forbids it.

NAMESPACE="np-ts-inert"
POLICY="vault-isolation"

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' has been deleted from '$NAMESPACE'"
    exit 1
fi

POD_APP=$(kubectl get pod vault -n "$NAMESPACE" -o jsonpath='{.metadata.labels.app}' 2> /dev/null || true)
if [[ "$POD_APP" != "vault" ]]; then
    echo "❌ Pod 'vault' is labelled app='${POD_APP:-<none>}'; its labels must not be changed"
    exit 1
fi

POD_LABELS=$(kubectl get pod vault -n "$NAMESPACE" -o json | jq -c '.metadata.labels // {}')
SELECTS=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o json \
    | jq --argjson labels "$POD_LABELS" '
        (.spec.podSelector.matchLabels // {}) as $sel
        | [$sel | to_entries[] | select($labels[.key] != .value)] | length == 0')

if [[ "$SELECTS" != "true" ]]; then
    SEL=$(kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" -o jsonpath='{.spec.podSelector}')
    echo "❌ '$POLICY' has podSelector '$SEL', which does not match the 'vault' Pod"
    exit 1
fi

echo "✅ '$POLICY' now applies to the 'vault' Pod, whose labels are unchanged"
exit 0
