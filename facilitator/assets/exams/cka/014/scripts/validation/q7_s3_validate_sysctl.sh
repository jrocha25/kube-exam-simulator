#!/bin/bash
set -e

# Both keys must be set in a file under /etc/sysctl.d (so they survive a reboot)
# and in effect now. The last assignment across the directory is what systemd
# applies, so read the files in the order sysctl --system does.
RESULT=$(ssh -o ConnectTimeout=10 -o BatchMode=yes node01 'bash -s' 2>/dev/null <<'REMOTE' || true
for key in net.ipv4.ip_forward net.ipv6.conf.all.forwarding; do
    persisted=$(cat $(ls /etc/sysctl.d/*.conf 2>/dev/null | sort) /dev/null 2>/dev/null \
        | sed -e 's/#.*//' -e 's/[[:space:]]//g' | grep "^${key}=" | tail -1 | cut -d= -f2)
    live=$(sysctl -n "$key" 2>/dev/null)
    echo "$key persisted=${persisted:-unset} live=${live:-unset}"
done
REMOTE
)

if [[ -z "$RESULT" ]]; then
    echo "❌ Cannot read the kernel parameters on node01"
    exit 1
fi

while read -r key persisted live; do
    if [[ "$persisted" != "persisted=1" ]]; then
        echo "❌ $key is not set to 1 in a file under /etc/sysctl.d on node01 ($persisted)"
        exit 1
    fi
    if [[ "$live" != "live=1" ]]; then
        echo "❌ $key is persisted but not in effect on node01 ($live)"
        exit 1
    fi
done <<< "$RESULT"

echo "✅ Both forwarding parameters are persisted under /etc/sysctl.d and in effect on node01"
exit 0
