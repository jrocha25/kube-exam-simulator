#!/bin/bash
set -e

USER="system:serviceaccount:rbac-app:report-runner"

for object in "serviceaccount/report-runner" "role/report-reader" "rolebinding/report-runner-read"; do
    if ! kubectl get "$object" -n rbac-app &> /dev/null; then
        echo "❌ '$object' does not exist in namespace 'rbac-app'"
        exit 1
    fi
done

check_denied() {
    local verb="$1" resource="$2" namespace="$3"
    local answer
    answer=$(kubectl auth can-i "$verb" "$resource" --as="$USER" -n "$namespace" 2>/dev/null || true)
    if [[ "$answer" == "yes" ]]; then
        echo "❌ '$USER' can '$verb' '$resource' in '$namespace'; the grant is too broad"
        exit 1
    fi
}

check_denied create pods rbac-app
check_denied delete pods rbac-app
check_denied get pods rbac-app-staging
check_denied get configmaps rbac-app-staging

echo "✅ The grant is read only and scoped to the 'rbac-app' namespace"
exit 0
