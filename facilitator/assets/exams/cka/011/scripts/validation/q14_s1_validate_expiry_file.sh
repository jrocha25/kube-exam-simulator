#!/bin/bash
set -e

# Recomputed from the node, never hardcoded. Both the bare date and openssl's
# "notAfter=" prefix are accepted, because the question asks for the date "as
# openssl reports it" and both readings of that are honest.

FILE="/tmp/exam/q14/etcd-expiry.txt"
CERT="/etc/kubernetes/pki/etcd/server.crt"

if [[ -f /tmp/exam/node-ssh-unavailable ]]; then
    echo "❌ There is no shell on the cluster nodes, so this question cannot be graded."
    exit 1
fi
if [[ ! -s "$FILE" ]]; then
    echo "❌ '$FILE' is missing or empty"
    exit 1
fi

EXPECTED=$(ssh -o ConnectTimeout=10 -o BatchMode=yes controlplane \
    "openssl x509 -noout -enddate -in ${CERT}" 2>/dev/null | tr -d '\r' | cut -d= -f2-)
if [[ -z "$EXPECTED" ]]; then
    echo "❌ Could not read ${CERT} on the control plane node"
    exit 1
fi

GOT=$(sed -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^notAfter=//' "$FILE" | grep -v '^$' | head -2)
LINES=$(printf '%s\n' "$GOT" | grep -c . || true)
if [[ "${LINES:-0}" -ne 1 ]]; then
    echo "❌ '$FILE' must contain the expiry date and nothing else (found ${LINES:-0} lines)"
    exit 1
fi

if [[ "$GOT" != "$EXPECTED" ]]; then
    echo "❌ '$FILE' says '${GOT}', the node reports '${EXPECTED}'"
    exit 1
fi

echo "✅ '$FILE' matches the live etcd server certificate"
exit 0
