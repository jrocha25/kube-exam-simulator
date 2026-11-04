#!/bin/bash

set -e

NAMESPACE="np-baseline"
POLICY="default-deny-ingress"

if ! kubectl get networkpolicy "$POLICY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ NetworkPolicy '$POLICY' not found in namespace '$NAMESPACE'"
    exit 1
fi

echo "✅ NetworkPolicy '$POLICY' exists in namespace '$NAMESPACE'"
exit 0
