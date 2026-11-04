#!/bin/bash
set -e

NAMESPACE="dev-team"
USER="mira"

check() {
    local expected="$1" verb="$2" resource="$3" ns="$4" extra="$5"
    local got
    # shellcheck disable=SC2086
    got=$(kubectl auth can-i "$verb" "$resource" --as="$USER" -n "$ns" $extra 2>/dev/null || true)
    if [[ "$got" != "$expected" ]]; then
        echo "❌ '$USER' can-i $verb $resource $extra -n $ns => '${got:-error}', expected '$expected'"
        return 1
    fi
    return 0
}

check yes list pods "$NAMESPACE" "" || exit 1
check yes get  pods "$NAMESPACE" "" || exit 1

# pods/log is a subresource: the positional form "get pods/log" asks about a Pod
# *named* log and answers yes whenever plain "get pods" is allowed, so it has to be
# requested with --subresource.
check yes get pods "$NAMESPACE" "--subresource=log" || exit 1

check no delete pods "$NAMESPACE" "" || exit 1
check no create pods "$NAMESPACE" "" || exit 1
check no list  pods default "" || exit 1
check no list  secrets "$NAMESPACE" "" || exit 1

echo "✅ '$USER' can read pods and pod logs in '$NAMESPACE' and nothing more"
exit 0
