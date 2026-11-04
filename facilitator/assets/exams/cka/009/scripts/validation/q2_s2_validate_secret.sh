#!/bin/bash

set -e

# The certificate content is randomised per attempt by the setup script, and the
# expected value is read back from the file here rather than hardcoded. A
# hardcoded comparison would grade typing, and an inline literal would satisfy a
# question that asked for a file.

NAMESPACE="kustom-gen"
SECRET="depot-ca"
KEY="ca.crt"
CA_FILE="/tmp/exam/q2/overlays/prod/depot-ca.pem"

if [[ ! -f "$CA_FILE" ]]; then
    echo "❌ '$CA_FILE' is missing; it is the file the Secret must be built from"
    exit 1
fi

if ! kubectl get secret "$SECRET" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Secret '$SECRET' not found in '$NAMESPACE' (a hashed name does not satisfy this)"
    exit 1
fi

TYPE=$(kubectl get secret "$SECRET" -n "$NAMESPACE" -o jsonpath='{.type}' 2> /dev/null || true)
if [[ "$TYPE" != "Opaque" ]]; then
    echo "❌ Secret '$SECRET' is of type '$TYPE', expected 'Opaque'"
    exit 1
fi

ENCODED=$(kubectl get secret "$SECRET" -n "$NAMESPACE" -o jsonpath="{.data.${KEY//./\\.}}" 2> /dev/null || true)
if [[ -z "$ENCODED" ]]; then
    echo "❌ Secret '$SECRET' has no key '$KEY'"
    exit 1
fi

if [[ "$(echo "$ENCODED" | base64 -d)" != "$(cat "$CA_FILE")" ]]; then
    echo "❌ Secret key '$KEY' does not match the contents of '$CA_FILE'"
    exit 1
fi

echo "✅ Secret '$SECRET' carries '$KEY' built from '$CA_FILE', with an unsuffixed name"
exit 0
