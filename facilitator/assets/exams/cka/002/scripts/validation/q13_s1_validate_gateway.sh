#!/bin/bash
set -e

# Check if Gateway exists
kubectl get gateway main-gateway -n gateway || {
    echo "Gateway main-gateway not found in namespace gateway"
    exit 1
}

# Check the gateway class
CLASS=$(kubectl get gateway main-gateway -n gateway -o jsonpath='{.spec.gatewayClassName}')
if [[ "$CLASS" != "traefik" ]]; then
    echo "Gateway is not using the traefik GatewayClass. Current class: $CLASS"
    exit 1
fi

# Check if Gateway is listening on port 80
PORT=$(kubectl get gateway main-gateway -n gateway -o jsonpath='{.spec.listeners[0].port}')
if [[ "$PORT" != "80" ]]; then
    echo "Gateway is not listening on port 80. Current port: $PORT"
    exit 1
fi

# Check protocol
PROTOCOL=$(kubectl get gateway main-gateway -n gateway -o jsonpath='{.spec.listeners[0].protocol}')
if [[ "$PROTOCOL" != "HTTP" ]]; then
    echo "Gateway is not using HTTP protocol. Current protocol: $PROTOCOL"
    exit 1
fi

# Check the Gateway was actually accepted and programmed by the controller.
# Give the controller a little time rather than reading the status once.
ACCEPTED=""
PROGRAMMED=""
for i in $(seq 1 12); do
    ACCEPTED=$(kubectl get gateway main-gateway -n gateway -o jsonpath='{.status.conditions[?(@.type=="Accepted")].status}' 2>/dev/null || true)
    PROGRAMMED=$(kubectl get gateway main-gateway -n gateway -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}' 2>/dev/null || true)
    if [[ "$ACCEPTED" == "True" && "$PROGRAMMED" == "True" ]]; then
        break
    fi
    sleep 5
done

if [[ "$ACCEPTED" != "True" ]]; then
    echo "Gateway is not Accepted by the controller. Current status: ${ACCEPTED:-<none>}"
    exit 1
fi

if [[ "$PROGRAMMED" != "True" ]]; then
    echo "Gateway is not Programmed by the controller. Current status: ${PROGRAMMED:-<none>}"
    exit 1
fi

echo "Gateway validation successful"
exit 0
