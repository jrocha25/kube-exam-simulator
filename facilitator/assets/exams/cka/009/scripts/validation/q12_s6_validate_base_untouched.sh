#!/bin/bash

set -e

# Constraint check, worth 1 mark: it passes on an untouched cluster. It is also
# what makes the rest of this question mean anything -- the whole point is that
# the placement policy lives in the overlay.

Q_DIR="/tmp/exam/q12"

if [[ ! -f "$Q_DIR/base.sha256" ]]; then
    echo "❌ '$Q_DIR/base.sha256' is missing; the question environment was not set up"
    exit 1
fi

if ! ( cd "$Q_DIR" && sha256sum -c base.sha256 ) &> /dev/null; then
    echo "❌ The base under '$Q_DIR/base' was modified; the policy belongs in the overlay"
    exit 1
fi

echo "✅ The base under '$Q_DIR/base' is unchanged"
exit 0
