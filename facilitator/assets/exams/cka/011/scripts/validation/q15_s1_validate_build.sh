#!/bin/bash
set -e

# Both overlays patch the ConfigMap, so removing it from the base alone makes
# this build fail with "no resource matches strategic merge patch". That is the
# loud half of the question and this step is where it shows up.

ROOT="/tmp/exam/q15/flightboard"

for env in staging prod; do
    if [[ ! -d "${ROOT}/${env}" ]]; then
        echo "❌ The '${env}' overlay is missing from ${ROOT}"
        exit 1
    fi
    if ! OUT=$(kubectl kustomize "${ROOT}/${env}" 2>&1); then
        echo "❌ The '${env}' overlay does not build"
        echo "   $(head -c 300 <<<"$OUT" | tr '\n' ' ')"
        exit 1
    fi
    if grep -q "refresh-config" <<<"$OUT"; then
        echo "❌ The '${env}' overlay still builds the 'refresh-config' ConfigMap"
        exit 1
    fi
done

echo "✅ Both overlays build and neither contains 'refresh-config'"
exit 0
