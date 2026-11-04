#!/bin/bash
set -e

# The two approved paths have to survive the repair. Like q5_s1 this passes on
# the seeded state -- an over-permissive policy allows these too -- so it is
# worth one mark and exists to stop a candidate "fixing" the namespace by
# denying everything.

NAMESPACE="net-apron"
CLIENT="apron"
ATTEMPTS=4

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicies are not enforced on this cluster, so this question cannot be graded."
    echo "   Rebuild with: ./start.sh --stop && ./start.sh --rebuild"
    exit 1
fi

reach() {
    local server="$1" port="$2" ip
    ip=$(kubectl get pod "$server" -n "$NAMESPACE" -o jsonpath='{.status.podIP}' 2>/dev/null || true)
    if [[ -z "$ip" ]]; then
        echo "❌ Pod '$server' in '$NAMESPACE' has no IP address"
        return 1
    fi
    for _ in $(seq 1 $ATTEMPTS); do
        if kubectl exec -n "$NAMESPACE" "$CLIENT" -- \
            timeout 4 bash -c "echo > /dev/tcp/${ip}/${port}" >/dev/null 2>&1; then
            return 0
        fi
        sleep 3
    done
    echo "❌ '$CLIENT' can no longer reach '$server' on port $port, which is approved traffic"
    return 1
}

reach gate 7001 || exit 1
reach fuel 7002 || exit 1

echo "✅ The approved paths from '$CLIENT' still work"
exit 0
