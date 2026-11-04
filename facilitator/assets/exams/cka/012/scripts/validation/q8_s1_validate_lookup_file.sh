#!/bin/bash
set -e

# The FQDN is grepped without its trailing dot: a resolver prints the name back
# on its "Name:" line in absolute form but without the dot, so requiring the dot
# would fail a correct answer. The dotless form matches either way.

FILE="/tmp/exam/q8/lookup.txt"
FQDN="station-index-0.station-index.dns-station.svc.cluster.local"

if [[ ! -s "$FILE" ]]; then
    echo "❌ '$FILE' is missing or empty"
    exit 1
fi

if ! grep -qF -- "$FQDN" "$FILE"; then
    echo "❌ '$FILE' does not mention '${FQDN}'"
    echo "   Found: $(head -c 200 "$FILE" | tr '\n' ' ')"
    exit 1
fi

echo "✅ '$FILE' holds a lookup of '${FQDN}'"
exit 0
