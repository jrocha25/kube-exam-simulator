#!/bin/bash
set -e

# The setup reserves all but ~150Mi of node01's memory for the system, sized from
# the node's real Capacity -- a kind node inherits the whole host's memory, so a
# fixed figure is a crippling reservation on a small host and no reservation at
# all on a large one. Unsolved, Allocatable is therefore a fraction of a percent
# of Capacity; solved, it is the high nineties. Assert the ratio rather than an
# absolute figure so this holds on an 8G laptop and a 64G workstation alike, and
# put the threshold where nothing but an actual fix can reach it.
MIN_RATIO_PERCENT=80

NODE=$(kubectl get nodes -l ck-x.io/alias=node01 -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$NODE" ]]; then
    echo "❌ No node is labelled ck-x.io/alias=node01"
    exit 1
fi

JSON=$(kubectl get node "$NODE" -o json)

READY=$(echo "$JSON" | jq -r '.status.conditions[] | select(.type=="Ready") | .status')
if [[ "$READY" != "True" ]]; then
    echo "❌ Node '$NODE' is not Ready"
    exit 1
fi

to_ki() {
    case "$1" in
        *Ki) echo "${1%Ki}" ;;
        *Mi) echo $(( ${1%Mi} * 1024 )) ;;
        *Gi) echo $(( ${1%Gi} * 1024 * 1024 )) ;;
        *)   echo $(( ${1:-0} / 1024 )) ;;
    esac
}

CAP=$(to_ki "$(echo "$JSON" | jq -r '.status.capacity.memory')")
ALLOC=$(to_ki "$(echo "$JSON" | jq -r '.status.allocatable.memory')")

if [[ "$CAP" -le 0 ]]; then
    echo "❌ Could not read the memory capacity of node '$NODE'"
    exit 1
fi

RATIO=$(( ALLOC * 100 / CAP ))
if [[ "$RATIO" -lt "$MIN_RATIO_PERCENT" ]]; then
    echo "❌ Node '$NODE' offers only ${RATIO}% of its memory as allocatable"
    echo "   (capacity ${CAP}Ki, allocatable ${ALLOC}Ki). The kubelet is still"
    echo "   holding most of the node back."
    exit 1
fi

echo "✅ Node '$NODE' offers ${RATIO}% of its memory as allocatable"
exit 0
