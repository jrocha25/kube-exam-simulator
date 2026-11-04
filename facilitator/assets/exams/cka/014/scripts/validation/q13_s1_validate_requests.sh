#!/bin/bash
set -e

NAMESPACE="crane-sim"
DEPLOYMENT="crane-sim"

NODE02=$(grep '^node02=' /tmp/exam/nodes.env | cut -d= -f2)
SPEC=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" -o json 2>/dev/null | jq -c '.spec.template.spec' || true)
ALLOC=$(kubectl get node "$NODE02" -o json 2>/dev/null | jq -c '.status.allocatable' || true)
if [[ -z "$SPEC" || -z "$ALLOC" ]]; then
    echo "❌ Deployment '$DEPLOYMENT' or node02 not found"
    exit 1
fi

# Quantities are compared in python: millicores and Ki/Mi/Gi suffixes.
python3 - "$SPEC" "$ALLOC" <<'PY'
import json, re, sys

spec, alloc = json.loads(sys.argv[1]), json.loads(sys.argv[2])
UNITS = {"": 1, "m": 1e-3, "k": 1e3, "M": 1e6, "G": 1e9, "T": 1e12,
         "Ki": 2**10, "Mi": 2**20, "Gi": 2**30, "Ti": 2**40}

def qty(value):
    if value is None:
        return None
    m = re.fullmatch(r"([0-9.]+)([a-zA-Z]*)", str(value))
    if not m or m.group(2) not in UNITS:
        return None
    return float(m.group(1)) * UNITS[m.group(2)]

def fail(msg):
    print("❌ " + msg)
    sys.exit(1)

containers = spec.get("initContainers", []) + spec.get("containers", [])
names = [c["name"] for c in containers]
if names != ["load-terrain", "simulator"]:
    fail(f"the Pod template must keep exactly load-terrain and simulator, found {names}")

reqs = [c.get("resources", {}).get("requests", {}) for c in containers]
for r in ("cpu", "memory"):
    values = [qty(x.get(r)) for x in reqs]
    if None in values:
        fail(f"every container must request {r}: {[x.get(r) for x in reqs]}")
    if values[0] != values[1]:
        fail(f"load-terrain and simulator must request the same {r}: {[x.get(r) for x in reqs]}")
    share = values[0] / qty(alloc[r])
    if share < 0.20:
        fail(f"each Pod requests {reqs[0][r]} {r}, {share:.0%} of node02's allocatable {alloc[r]}; at least a fifth is required")
    if share > 0.34:
        fail(f"each Pod requests {reqs[0][r]} {r}, {share:.0%} of node02's allocatable {alloc[r]}; three such Pods cannot fit")

print(f"✅ init and main containers request the same share of node02 ({reqs[0]['cpu']} CPU, {reqs[0]['memory']} memory)")
PY
