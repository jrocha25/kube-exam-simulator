#!/bin/bash
set -e

CSR_NAME="mira-access"
EXPECTED_SIGNER="kubernetes.io/kube-apiserver-client"
CERT_FILE="/tmp/exam/q3/mira.crt"
KEY_FILE="/tmp/exam/q3/mira.key"

JSON=$(kubectl get csr "$CSR_NAME" -o json 2>/dev/null || true)
if [[ -z "$JSON" ]]; then
    echo "❌ CertificateSigningRequest '$CSR_NAME' not found"
    exit 1
fi

SIGNER=$(echo "$JSON" | jq -r '.spec.signerName')
if [[ "$SIGNER" != "$EXPECTED_SIGNER" ]]; then
    echo "❌ '$CSR_NAME' uses signer '$SIGNER', expected '$EXPECTED_SIGNER'"
    exit 1
fi

APPROVED=$(echo "$JSON" | jq -r '[.status.conditions[]? | select(.type=="Approved" and .status=="True")] | length')
if [[ "$APPROVED" -lt 1 ]]; then
    echo "❌ '$CSR_NAME' has not been approved"
    exit 1
fi

ISSUED=$(echo "$JSON" | jq -r '.status.certificate // empty')
if [[ -z "$ISSUED" ]]; then
    echo "❌ '$CSR_NAME' is approved but no certificate was issued"
    exit 1
fi

if [[ ! -s "$KEY_FILE" ]]; then
    echo "❌ Private key '$KEY_FILE' is missing or empty"
    exit 1
fi

if [[ ! -s "$CERT_FILE" ]]; then
    echo "❌ Issued certificate '$CERT_FILE' is missing or empty"
    exit 1
fi

SUBJECT=$(openssl x509 -in "$CERT_FILE" -noout -subject 2>/dev/null || true)
if ! grep -q "CN *= *mira" <<<"$SUBJECT"; then
    echo "❌ '$CERT_FILE' has subject '$SUBJECT', expected common name 'mira'"
    exit 1
fi
if ! grep -q "O *= *developers" <<<"$SUBJECT"; then
    echo "❌ '$CERT_FILE' has subject '$SUBJECT', expected organization 'developers'"
    exit 1
fi

echo "✅ '$CSR_NAME' is approved and issued for CN=mira, O=developers"
exit 0
