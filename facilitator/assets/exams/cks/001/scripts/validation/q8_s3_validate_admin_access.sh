#!/bin/bash

NAMESPACE="api-restrict"
ADMIN_POD="admin-pod"
RESTRICTED_POD="restricted-pod"

echo "🔍 Getting Kubernetes API Server IP..."
API_SERVER_IP=$(kubectl get endpoints kubernetes -o jsonpath='{.subsets[0].addresses[0].ip}')
if [ -z "$API_SERVER_IP" ]; then
  echo "❌ Could not find API server IP"
  exit 1
fi
echo "✅ API Server IP: $API_SERVER_IP"

# Function to check pod and label
check_pod_and_label() {
  local pod_name=$1
  local expected_label=$2

  echo "🔍 Checking pod '$pod_name' in namespace '$NAMESPACE'..."

  kubectl get pod "$pod_name" -n "$NAMESPACE" &> /dev/null
  if [ $? -ne 0 ]; then
    echo "❌ Pod '$pod_name' not found"
    exit 1
  fi

  label=$(kubectl get pod "$pod_name" -n "$NAMESPACE" -o jsonpath='{.metadata.labels.role}')
  if [ "$label" != "$expected_label" ]; then
    echo "❌ Pod '$pod_name' does not have label 'role=$expected_label'"
    exit 1
  fi

  echo "✅ Pod '$pod_name' has correct label 'role=$expected_label'"
}

# Function to test connectivity
test_connectivity() {
  local pod_name=$1
  local expect_success=$2

  echo "🚀 Testing connectivity from '$pod_name' to API server..."

  kubectl exec -n "$NAMESPACE" "$pod_name" -- nc -z -w2 "$API_SERVER_IP" 443 &> /dev/null
  result=$?

  if [ $expect_success -eq 1 ] && [ $result -eq 0 ]; then
    echo "✅ '$pod_name' can access the API server as expected"
  elif [ $expect_success -eq 1 ]; then
    echo "❌ '$pod_name' could NOT access the API server (but it should)"
    exit 1
  elif [ $expect_success -eq 0 ] && [ $result -ne 0 ]; then
    echo "✅ '$pod_name' is correctly restricted from accessing the API server"
  else
    echo "❌ '$pod_name' accessed the API server (but it should NOT)"
    exit 1
  fi
}

echo "🔎 Validating..."

check_pod_and_label "$ADMIN_POD" "admin"
check_pod_and_label "$RESTRICTED_POD" "restricted"

test_connectivity "$ADMIN_POD" 1        # Should succeed
test_connectivity "$RESTRICTED_POD" 0   # Should fail

echo "🎉 All validations passed!"
