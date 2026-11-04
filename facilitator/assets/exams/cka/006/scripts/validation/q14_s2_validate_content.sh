#!/bin/bash
set -e

RENDERED="/tmp/exam/q14/rendered.yaml"

if [[ ! -s "$RENDERED" ]]; then
    echo "❌ '$RENDERED' is missing or empty"
    exit 1
fi

# Parse rather than grep: a rendered manifest that merely mentions "4" somewhere
# is not a Deployment with four replicas.
DOC=$(python3 -c "
import sys, json
try:
    import yaml
except ImportError:
    sys.exit(3)
docs = [d for d in yaml.safe_load_all(open('$RENDERED')) if d]
for d in docs:
    if d.get('kind') == 'Deployment' and d.get('metadata', {}).get('name') == 'reports':
        print(json.dumps(d)); break
" 2>/dev/null || true)

if [[ -z "$DOC" ]]; then
    # No PyYAML on the jumphost: fall back to kubectl, which understands YAML.
    DOC=$(kubectl create --dry-run=client -o json -f "$RENDERED" 2>/dev/null \
        | jq -c 'if .kind == "List" then (.items[] | select(.kind=="Deployment" and .metadata.name=="reports")) else select(.kind=="Deployment" and .metadata.name=="reports") end' \
        | head -1 || true)
fi

if [[ -z "$DOC" ]]; then
    echo "❌ '$RENDERED' contains no Deployment named 'reports'"
    exit 1
fi

NS=$(jq -r '.metadata.namespace // empty' <<<"$DOC")
REPLICAS=$(jq -r '.spec.replicas' <<<"$DOC")
IMAGE=$(jq -r '.spec.template.spec.containers[0].image' <<<"$DOC")

if [[ "$NS" != "kustom-fix" ]]; then
    echo "❌ The rendered Deployment is in namespace '${NS:-<none>}', expected 'kustom-fix'"
    exit 1
fi
if [[ "$REPLICAS" != "4" ]]; then
    echo "❌ The rendered Deployment declares $REPLICAS replicas, expected 4"
    exit 1
fi
if [[ "$IMAGE" != "nginx:1.27.4" ]]; then
    echo "❌ The rendered Deployment runs '$IMAGE', expected 'nginx:1.27.4'"
    exit 1
fi

echo "✅ The rendered Deployment has the required namespace, replicas and image"
exit 0
