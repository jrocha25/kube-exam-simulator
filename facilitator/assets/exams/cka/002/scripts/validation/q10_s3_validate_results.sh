#!/bin/bash
set -e

# Check if results file exists in the pod
FILE_CHECK=$(kubectl exec -n dns-config dns-tester -- test -f /tmp/dns-test.txt && echo "exists" || echo "not found")
if [ "$FILE_CHECK" = "not found" ]; then
    echo "DNS test results file not found"
    exit 1
fi

# Check if file has content
CONTENT=$(kubectl exec -n dns-config dns-tester -- cat /tmp/dns-test.txt 2>/dev/null || echo "")
if [ -z "$CONTENT" ]; then
    echo "DNS test results file is empty"
    exit 1
fi

# Verify file contains required information
if ! echo "$CONTENT" | grep -q "dns-svc.dns-config.svc.cluster.local"; then
    echo "FQDN resolution results not found in file"
    exit 1
fi

# The FQDN alone is satisfied by echoing the name into the file. Real lookup
# output also carries the address the name resolved to, which is not guessable.
SVC_IP=$(kubectl get service dns-svc -n dns-config -o jsonpath='{.spec.clusterIP}' 2>/dev/null || true)
if [[ -z "$SVC_IP" ]]; then
    echo "Service dns-svc not found in namespace dns-config"
    exit 1
fi

if ! echo "$CONTENT" | grep -q "$SVC_IP"; then
    echo "The results file does not contain the address dns-svc resolves to ($SVC_IP);"
    echo "it must hold the actual output of the lookup run inside the pod"
    exit 1
fi

exit 0 