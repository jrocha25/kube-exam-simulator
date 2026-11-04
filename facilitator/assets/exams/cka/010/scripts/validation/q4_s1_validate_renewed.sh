#!/bin/bash
set -e

BEFORE="/tmp/exam/q4/before.env"

if [[ ! -s "$BEFORE" ]]; then
    echo "❌ Setup did not record the certificate expiry dates, so this step cannot be graded"
    exit 1
fi
# shellcheck disable=SC1090
source "$BEFORE"

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes controlplane true >/dev/null 2>&1; then
    echo "❌ Cannot reach the control plane node over SSH"
    exit 1
fi

for cert in apiserver apiserver-kubelet-client front-proxy-client; do
    var="${cert//-/_}"
    recorded="${!var:-}"
    if [[ -z "$recorded" ]]; then
        echo "❌ No recorded expiry for ${cert}.crt"
        exit 1
    fi
    END=$(ssh -o ConnectTimeout=10 controlplane \
        "openssl x509 -in /etc/kubernetes/pki/${cert}.crt -noout -enddate 2>/dev/null | cut -d= -f2" || true)
    if [[ -z "$END" ]]; then
        echo "❌ Could not read /etc/kubernetes/pki/${cert}.crt on the control plane"
        exit 1
    fi
    NOW=$(date -d "$END" +%s)
    if [[ "$NOW" -le "$recorded" ]]; then
        echo "❌ ${cert}.crt still expires at $(date -u -d @"$NOW" +%FT%TZ) -- it was not renewed"
        exit 1
    fi
done

echo "✅ The control plane certificates were renewed"
exit 0
