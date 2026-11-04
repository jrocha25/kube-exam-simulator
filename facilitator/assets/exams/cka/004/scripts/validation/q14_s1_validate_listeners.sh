#!/bin/bash
set -e

NAMESPACE="edge-shared"
GATEWAY="shared-gw"

if ! kubectl get gateway "$GATEWAY" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Gateway '$GATEWAY' not found in namespace '$NAMESPACE'"
    exit 1
fi

SPEC=$(kubectl get gateway "$GATEWAY" -n "$NAMESPACE" -o json)

KEPT=$(echo "$SPEC" | jq '[.spec.listeners // [] | .[]
    | select(.name == "http" and .port == 80 and .protocol == "HTTP")
    | select(.hostname == "www.helioscale.io")
    | select(.allowedRoutes.namespaces.from == "Same")] | length')
if [[ "$KEPT" == "0" ]]; then
    echo "❌ The original listener 'http' on www.helioscale.io must be kept unchanged"
    exit 1
fi

PARTNERS=$(echo "$SPEC" | jq '[.spec.listeners // [] | .[]
    | select(.name == "partners" and .port == 80 and .protocol == "HTTP")
    | select(.hostname == "partners.helioscale.io")] | length')
if [[ "$PARTNERS" == "0" ]]; then
    echo "❌ Gateway '$GATEWAY' has no listener named 'partners' on partners.helioscale.io port 80/HTTP"
    exit 1
fi

FROM=$(echo "$SPEC" | jq -r '[.spec.listeners // [] | .[] | select(.name == "partners") | .allowedRoutes.namespaces.from] | first // empty')
if [[ "$FROM" != "Selector" ]]; then
    echo "❌ The 'partners' listener must accept routes from namespaces selected by a label (allowedRoutes.namespaces.from: '${FROM:-<none>}')"
    exit 1
fi

LABEL=$(echo "$SPEC" | jq -r '[.spec.listeners // [] | .[] | select(.name == "partners")
    | .allowedRoutes.namespaces.selector.matchLabels["gateway-access"]] | first // empty')
if [[ "$LABEL" != "allowed" ]]; then
    echo "❌ The 'partners' listener must select namespaces labelled 'gateway-access=allowed' (got: 'gateway-access=${LABEL:-<none>}')"
    exit 1
fi

ACCEPTED=""
PROGRAMMED=""
for _ in $(seq 1 12); do
    ACCEPTED=$(kubectl get gateway "$GATEWAY" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)
    PROGRAMMED=$(kubectl get gateway "$GATEWAY" -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)
    if [[ "$ACCEPTED" == "True" ]] && [[ "$PROGRAMMED" == "True" ]]; then
        break
    fi
    sleep 5
done

if [[ "$ACCEPTED" != "True" ]] || [[ "$PROGRAMMED" != "True" ]]; then
    echo "❌ Gateway '$GATEWAY' is not Accepted and Programmed (Accepted: '${ACCEPTED:-<none>}', Programmed: '${PROGRAMMED:-<none>}')"
    exit 1
fi

echo "✅ Gateway '$GATEWAY' exposes both listeners and the 'partners' listener is restricted by namespace label"
exit 0
