#!/bin/bash
set -e

# Probes the policies from the Pods the question already asks for, by Pod IP.
# Nothing is created here: a client Pod of its own would not be covered by the
# candidate's policies, so it could never prove anything about them.

NAMESPACE="network"
CONNECT_TIMEOUT=4

pod_name() {
    kubectl get pods -n "$NAMESPACE" -l "app=$1" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true
}

pod_ip() {
    kubectl get pods -n "$NAMESPACE" -l "app=$1" \
        --field-selector=status.phase=Running \
        -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || true
}

# Reachability is only meaningful once every tier is actually up.
for _ in $(seq 1 12); do
    WEB_POD=$(pod_name web); API_POD=$(pod_name api); DB_POD=$(pod_name db)
    [[ -n "$WEB_POD" && -n "$API_POD" && -n "$DB_POD" ]] && break
    sleep 5
done

WEB_POD=$(pod_name web); API_POD=$(pod_name api); DB_POD=$(pod_name db)
for tier in web:$WEB_POD api:$API_POD db:$DB_POD; do
    if [[ -z "${tier#*:}" ]]; then
        echo "❌ No Running Pod labelled 'app=${tier%%:*}' in namespace '$NAMESPACE'"
        exit 1
    fi
done

API_IP=$(pod_ip api)
DB_IP=$(pod_ip db)
if [[ -z "$API_IP" || -z "$DB_IP" ]]; then
    echo "❌ Could not read the Pod IPs of the api and db tiers"
    exit 1
fi

# bash's /dev/tcp needs no tooling inside the image, so this works against the
# stock nginx and postgres containers.
probe() {
    local client=$1 host=$2 port=$3
    kubectl exec -n "$NAMESPACE" "$client" -- \
        timeout "$CONNECT_TIMEOUT" bash -c "echo > /dev/tcp/$host/$port" &> /dev/null
}

if ! probe "$WEB_POD" "$API_IP" 80; then
    echo "❌ 'web' cannot reach 'api' on port 80, and the policies must allow that"
    exit 1
fi

if ! probe "$API_POD" "$DB_IP" 5432; then
    echo "❌ 'api' cannot reach 'db' on port 5432, and the policies must allow that"
    exit 1
fi

if probe "$WEB_POD" "$DB_IP" 5432; then
    echo "❌ 'web' can still reach 'db' on port 5432, and the policies must deny that"
    exit 1
fi

echo "✅ The policies allow web to api and api to db, and block web to db"
exit 0
