#!/bin/bash
set -e

APISERVICE="v1beta1.metrics.k8s.io"

if [[ -f /tmp/exam/metrics-server-unavailable ]]; then
    echo "❌ The metrics-server manifest could not be downloaded during setup, so this question has no input file."
    echo "   This jumphost has no route to github.com."
    exit 1
fi

if ! kubectl get apiservice "$APISERVICE" >/dev/null 2>&1; then
    echo "❌ The APIService '$APISERVICE' does not exist -- the Metrics API is not registered"
    exit 1
fi

# Registration is instant; becoming Available means it has actually scraped a
# kubelet, which is the part that does not work out of the box on this cluster.
for _ in $(seq 1 12); do
    STATUS=$(kubectl get apiservice "$APISERVICE" \
        -o jsonpath='{.status.conditions[?(@.type=="Available")].status}' 2>/dev/null || true)
    [[ "$STATUS" == "True" ]] && break
    sleep 5
done

if [[ "$STATUS" != "True" ]]; then
    REASON=$(kubectl get apiservice "$APISERVICE" \
        -o jsonpath='{.status.conditions[?(@.type=="Available")].message}' 2>/dev/null || true)
    echo "❌ The APIService '$APISERVICE' is not Available (status ${STATUS:-unknown})"
    [[ -n "$REASON" ]] && echo "   ${REASON}"
    exit 1
fi

echo "✅ The Metrics API is registered and Available"
exit 0
