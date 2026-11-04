#!/usr/bin/env bash
#
# Developer deploy: build every component from local source, then start.
#
# This is a thin wrapper around ./start.sh so there is only one startup path to
# maintain. If you just want to run CK-X, use ./start.sh instead — it uses the
# prebuilt components and is much faster.

set -euo pipefail

SCRIPT_DIR=$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)

exec "$SCRIPT_DIR/start.sh" --rebuild "$@"
