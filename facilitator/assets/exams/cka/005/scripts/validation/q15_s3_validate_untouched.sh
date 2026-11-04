#!/bin/bash
set -e

BASE_SUMS="/tmp/exam/q15/base.sha256"

if [[ ! -f "$BASE_SUMS" ]]; then
    echo "❌ '$BASE_SUMS' is missing; the base checksums cannot be verified"
    exit 1
fi

if ! ( cd /tmp/exam/q15 && sha256sum --status -c "$BASE_SUMS" ); then
    echo "❌ The shared base under /tmp/exam/q15/base was modified"
    exit 1
fi

COUNT=$(kubectl get deployments -n kustom-fix --no-headers 2>/dev/null | wc -l)
if [[ "$COUNT" != "0" ]]; then
    echo "❌ The 'kustom-fix' namespace contains $COUNT Deployment(s); the overlay was not meant to be applied"
    exit 1
fi

echo "✅ The shared base is unchanged and nothing was applied to 'kustom-fix'"
exit 0
