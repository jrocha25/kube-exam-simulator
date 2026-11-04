#!/bin/bash
set -e

# Provenance. Two values are required and neither can be typed from memory:
#
#   * the current IP of station-index-0, which changes on every warm-up
#   * the cluster DNS service address, which a resolver running inside a Pod
#     prints as its server and a shell on the jumphost would never mention
#
# Together they mean the file can only have come from a lookup that really ran in
# the cluster, which is what makes this question about DNS rather than about echo.

FILE="/tmp/exam/q8/lookup.txt"
NAMESPACE="dns-station"
POD="station-index-0"

if [[ ! -s "$FILE" ]]; then
    echo "❌ '$FILE' is missing or empty"
    exit 1
fi

POD_IP=$(kubectl get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null || true)
if [[ -z "$POD_IP" ]]; then
    echo "❌ Pod '$POD' in '$NAMESPACE' has no IP; it is part of the lab and should be Running"
    exit 1
fi

if ! grep -qF -- "$POD_IP" "$FILE"; then
    echo "❌ '$FILE' does not contain the current address of '$POD' (${POD_IP})"
    echo "   Found: $(head -c 300 "$FILE" | tr '\n' ' ')"
    echo "   A headless Service publishes one A record per Pod; that record resolves to the Pod's own IP."
    exit 1
fi

DNS_IP=$(kubectl get service kube-dns -n kube-system -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
if [[ -n "$DNS_IP" ]] && ! grep -qF -- "$DNS_IP" "$FILE"; then
    echo "❌ '$FILE' does not name the cluster DNS server (${DNS_IP})"
    echo "   The lookup has to be run from inside a Pod, and the whole output saved:"
    echo "   a resolver reports the server it asked."
    exit 1
fi

echo "✅ '$FILE' is an in-cluster lookup that resolved '$POD' to ${POD_IP}"
exit 0
