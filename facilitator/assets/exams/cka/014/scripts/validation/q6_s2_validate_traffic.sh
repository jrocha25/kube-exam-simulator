#!/bin/bash
set -e

API_NS="harbor-api"

if [[ -f /tmp/exam/networkpolicy-unavailable ]]; then
    echo "❌ NetworkPolicy is not enforced on this cluster, so traffic cannot be graded"
    exit 1
fi

# Nothing to grade without the candidate's own policy: the seeded default deny
# alone already blocks the denied paths.
if [[ -z "$(kubectl get networkpolicy -n "$API_NS" -o name 2>/dev/null | grep -v default-deny-ingress)" ]]; then
    echo "❌ No policy besides default-deny-ingress exists in '$API_NS'"
    exit 1
fi

IP=$(kubectl get pod harbor-api -n "$API_NS" -o jsonpath='{.status.podIP}' 2>/dev/null || true)
if [[ -z "$IP" ]]; then
    echo "❌ The harbor-api Pod has no IP"
    exit 1
fi

probe() {
    kubectl exec -n "$1" "$2" -- wget -qO- -T 3 "http://$IP:$3/" 2>/dev/null | grep -q harbor-api
}

ALLOWED=no
for _ in $(seq 1 6); do
    probe harbor-ui crane-ui 8080 && { ALLOWED=yes; break; }
    sleep 5
done
if [[ "$ALLOWED" != yes ]]; then
    echo "❌ crane-ui in harbor-ui cannot reach harbor-api on 8080"
    exit 1
fi

for denied in "harbor-ui berth-ui 8080" "harbor-tools crane-ui 8080" "harbor-ui crane-ui 9090"; do
    set -- $denied
    for _ in 1 2; do
        if probe "$1" "$2" "$3"; then
            echo "❌ $2 in $1 can reach harbor-api on $3; the policy is wider than it has to be"
            exit 1
        fi
    done
done

echo "✅ Only crane-ui in harbor-ui reaches harbor-api, and only on 8080"
exit 0
