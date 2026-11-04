#!/bin/bash
set -e

POLICY_DIR="/tmp/exam/q6/policies"
PRISTINE_DIR="/tmp/exam/q6/.pristine"

for FILE in policy-a.yaml policy-b.yaml policy-c.yaml; do
    if [[ ! -f "$POLICY_DIR/$FILE" ]]; then
        echo "❌ '$POLICY_DIR/$FILE' is missing"
        exit 1
    fi
    if ! diff -q "$PRISTINE_DIR/$FILE" "$POLICY_DIR/$FILE" > /dev/null; then
        echo "❌ '$POLICY_DIR/$FILE' was modified. The candidate policies must be applied exactly as provided"
        exit 1
    fi
done

echo "✅ The three candidate policy files are unmodified"
exit 0
