#!/bin/bash
set -e

# The fix the question is really about. The Pod asks for a label no node carried,
# and the only way to place it without touching the Pod is to put that label on
# the node the question names.

ALIAS="node02"
LABEL_KEY="seismo.io/duty"
LABEL_VALUE="plotting"

NODE=$(awk -F= -v a="$ALIAS" '$1==a {print $2}' /tmp/exam/nodes.env 2>/dev/null | head -1)
if [[ -z "$NODE" ]]; then
    NODE=$(kubectl get nodes -l "ck-x.io/alias=${ALIAS}" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
fi
if [[ -z "$NODE" ]]; then
    echo "❌ No node carries the label ck-x.io/alias=${ALIAS}"
    exit 1
fi

GOT=$(kubectl get node "$NODE" -o jsonpath="{.metadata.labels['seismo\.io/duty']}" 2>/dev/null || true)
if [[ "$GOT" != "$LABEL_VALUE" ]]; then
    echo "❌ Node '${NODE}' (${ALIAS}) carries ${LABEL_KEY}='${GOT:-unset}', expected '${LABEL_VALUE}'"
    exit 1
fi

echo "✅ Node '${NODE}' (${ALIAS}) carries ${LABEL_KEY}=${LABEL_VALUE}"
exit 0
