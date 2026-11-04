#!/bin/bash
set -e

NAMESPACE="web-shop"
INGRESS="shop-web-ing"

if ! kubectl get ingress "$INGRESS" -n "$NAMESPACE" &> /dev/null; then
    echo "❌ Ingress '$INGRESS' not found in namespace '$NAMESPACE'"
    exit 1
fi

CLASS=$(kubectl get ingress "$INGRESS" -n "$NAMESPACE" -o jsonpath='{.spec.ingressClassName}')
if [[ "$CLASS" != "traefik" ]]; then
    echo "❌ Incorrect ingressClassName. Expected 'traefik', got '$CLASS'"
    exit 1
fi

HOST=$(kubectl get ingress "$INGRESS" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].host}')
if [[ "$HOST" != "shop.example.com" ]]; then
    echo "❌ Incorrect host. Expected 'shop.example.com', got '$HOST'"
    exit 1
fi

PATH_VALUE=$(kubectl get ingress "$INGRESS" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].http.paths[0].path}')
if [[ "$PATH_VALUE" != "/" ]]; then
    echo "❌ Incorrect path. Expected '/', got '$PATH_VALUE'"
    exit 1
fi

PATH_TYPE=$(kubectl get ingress "$INGRESS" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].http.paths[0].pathType}')
if [[ "$PATH_TYPE" != "Prefix" ]]; then
    echo "❌ Incorrect pathType. Expected 'Prefix', got '$PATH_TYPE'"
    exit 1
fi

BACKEND_SVC=$(kubectl get ingress "$INGRESS" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}')
if [[ "$BACKEND_SVC" != "shop-web-svc" ]]; then
    echo "❌ Incorrect backend service. Expected 'shop-web-svc', got '$BACKEND_SVC'"
    exit 1
fi

BACKEND_PORT=$(kubectl get ingress "$INGRESS" -n "$NAMESPACE" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.port.number}')
if [[ "$BACKEND_PORT" != "80" ]]; then
    echo "❌ Incorrect backend service port. Expected '80', got '$BACKEND_PORT'"
    exit 1
fi

echo "✅ Ingress '$INGRESS' routes shop.example.com to 'shop-web-svc' on port 80"
exit 0
