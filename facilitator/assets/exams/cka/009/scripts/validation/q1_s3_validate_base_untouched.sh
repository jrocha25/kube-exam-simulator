#!/bin/bash

set -e

# A constraint check: it passes on an untouched cluster, so it is worth 1 mark.
# The checksums were recorded by the setup script.

Q_DIR="/tmp/exam/q1"

if [[ ! -f "$Q_DIR/base.sha256" ]]; then
    echo "❌ '$Q_DIR/base.sha256' is missing; the question environment was not set up"
    exit 1
fi

if ! ( cd "$Q_DIR" && sha256sum -c base.sha256 ) &> /dev/null; then
    echo "❌ The base under '$Q_DIR/base' was modified; the overlay had to do this work"
    exit 1
fi

echo "✅ The base under '$Q_DIR/base' is unchanged"
exit 0
