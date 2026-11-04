#!/bin/bash
set -e

# Renewing the file is half the work: the API server keeps serving the
# certificate it loaded at start until it is restarted. Compare what the
# running server presents with what is on disk.
API_HOST="k8s-api-server"
API_PORT=6443

if ! ssh -o ConnectTimeout=10 -o BatchMode=yes controlplane true >/dev/null 2>&1; then
    echo "❌ Cannot reach the control plane node over SSH"
    exit 1
fi

ON_DISK=$(ssh -o ConnectTimeout=10 controlplane \
    "openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -enddate 2>/dev/null | cut -d= -f2" || true)
if [[ -z "$ON_DISK" ]]; then
    echo "❌ Could not read apiserver.crt on the control plane"
    exit 1
fi

# The API server can be mid-restart if the candidate just did this; bounded retry.
for _ in $(seq 1 6); do
    SERVED=$(echo | timeout 10 openssl s_client -connect "${API_HOST}:${API_PORT}" 2>/dev/null \
        | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2 || true)
    [[ -n "$SERVED" ]] && break
    sleep 5
done
if [[ -z "$SERVED" ]]; then
    echo "❌ Could not read the certificate the API server presents on port ${API_PORT}"
    exit 1
fi

if [[ "$(date -d "$SERVED" +%s)" != "$(date -d "$ON_DISK" +%s)" ]]; then
    echo "❌ The API server still presents a certificate expiring $SERVED, but apiserver.crt on disk expires $ON_DISK -- it was not restarted"
    exit 1
fi

BEFORE="/tmp/exam/q4/before.env"
if [[ -s "$BEFORE" ]]; then
    # shellcheck disable=SC1090
    source "$BEFORE"
    if [[ -n "${apiserver:-}" && "$(date -d "$SERVED" +%s)" -le "$apiserver" ]]; then
        echo "❌ The API server presents the original certificate (expires $SERVED)"
        exit 1
    fi
fi

echo "✅ The API server serves the renewed certificate (expires $SERVED)"
exit 0
