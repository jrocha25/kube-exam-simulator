#!/bin/bash
set -e

PKG="harbor-cri-shim"

STATE=$(ssh -o ConnectTimeout=10 -o BatchMode=yes node01 \
    "dpkg-query -W -f='\${Status}|\${Version}' $PKG" 2>/dev/null </dev/null || true)
if [[ "$STATE" != "install ok installed|1.4.2" ]]; then
    echo "❌ Package $PKG 1.4.2 is not installed on node01 (dpkg reports '${STATE:-nothing}')"
    exit 1
fi

echo "✅ $PKG 1.4.2 is installed on node01"
exit 0
