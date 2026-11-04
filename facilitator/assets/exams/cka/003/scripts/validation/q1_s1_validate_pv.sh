#!/bin/bash
set -e

PV_NAME="logs-pv"

if ! kubectl get pv "$PV_NAME" &> /dev/null; then
    echo "❌ PersistentVolume '$PV_NAME' not found"
    exit 1
fi

CAPACITY=$(kubectl get pv "$PV_NAME" -o jsonpath='{.spec.capacity.storage}')
if [[ "$CAPACITY" != "2Gi" ]]; then
    echo "❌ Incorrect capacity. Expected '2Gi', got '$CAPACITY'"
    exit 1
fi

ACCESS_MODE=$(kubectl get pv "$PV_NAME" -o jsonpath='{.spec.accessModes[0]}')
if [[ "$ACCESS_MODE" != "ReadWriteOnce" ]]; then
    echo "❌ Incorrect access mode. Expected 'ReadWriteOnce', got '$ACCESS_MODE'"
    exit 1
fi

SC=$(kubectl get pv "$PV_NAME" -o jsonpath='{.spec.storageClassName}')
if [[ "$SC" != "manual" ]]; then
    echo "❌ Incorrect storage class name. Expected 'manual', got '$SC'"
    exit 1
fi

RECLAIM=$(kubectl get pv "$PV_NAME" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}')
if [[ "$RECLAIM" != "Retain" ]]; then
    echo "❌ Incorrect reclaim policy. Expected 'Retain', got '$RECLAIM'"
    exit 1
fi

HOST_PATH=$(kubectl get pv "$PV_NAME" -o jsonpath='{.spec.hostPath.path}')
if [[ "$HOST_PATH" != "/mnt/logs-data" ]]; then
    echo "❌ Incorrect hostPath. Expected '/mnt/logs-data', got '$HOST_PATH'"
    exit 1
fi

HOST_PATH_TYPE=$(kubectl get pv "$PV_NAME" -o jsonpath='{.spec.hostPath.type}')
if [[ "$HOST_PATH_TYPE" != "DirectoryOrCreate" ]]; then
    echo "❌ Incorrect hostPath type. Expected 'DirectoryOrCreate', got '$HOST_PATH_TYPE'"
    exit 1
fi

echo "✅ PersistentVolume '$PV_NAME' is configured correctly"
exit 0
