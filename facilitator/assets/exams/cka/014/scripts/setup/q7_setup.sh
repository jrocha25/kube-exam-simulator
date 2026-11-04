#!/bin/bash
set -e

# Question 7: prepare node01 the way a new node is prepared before it joins --
# install a package from a .deb, enable its service, persist kernel parameters.
# The package is built here with dpkg-deb, so it needs no network and no repo.
#
# Only network-namespaced sysctls are used: a kind node is a privileged
# container, and a kernel-wide key written from it would change the host.
# net.bridge.* is not available inside a kind node at all.

if [ -f /tmp/exam/node-ssh-unavailable ]; then
    echo "WARNING: no shell on node01, question 7 cannot be staged"
    exit 0
fi

ssh -o ConnectTimeout=10 node01 'bash -s' <<'REMOTE'
set -e
PKG=harbor-cri-shim
VERSION=1.4.2
BUILD=$(mktemp -d)

systemctl disable --now "$PKG" >/dev/null 2>&1 || true
dpkg -r "$PKG" >/dev/null 2>&1 || true
rm -f /etc/sysctl.d/*harbor* /root/${PKG}_*.deb
sysctl -qw net.ipv6.conf.all.forwarding=0

mkdir -p "$BUILD/DEBIAN" "$BUILD/usr/local/bin" "$BUILD/usr/lib/systemd/system"
cat > "$BUILD/DEBIAN/control" <<CONTROL
Package: $PKG
Version: $VERSION
Architecture: all
Maintainer: Harbor Platform Team <platform@harbor.local>
Section: admin
Priority: optional
Description: CRI shim for the harbor crane telemetry runtime
 Exposes a heartbeat under /run/harbor-cri-shim for the node agents.
CONTROL

cat > "$BUILD/usr/local/bin/$PKG" <<'BIN'
#!/bin/sh
mkdir -p /run/harbor-cri-shim
while true; do
    date -u +%Y-%m-%dT%H:%M:%SZ > /run/harbor-cri-shim/heartbeat
    sleep 10
done
BIN
chmod 0755 "$BUILD/usr/local/bin/$PKG"

cat > "$BUILD/usr/lib/systemd/system/$PKG.service" <<UNIT
[Unit]
Description=Harbor CRI shim
After=network-online.target

[Service]
ExecStart=/usr/local/bin/$PKG
Restart=always

[Install]
WantedBy=multi-user.target
UNIT

dpkg-deb --root-owner-group --build "$BUILD" "/root/${PKG}_${VERSION}_all.deb" >/dev/null
rm -rf "$BUILD"
ls -l /root/${PKG}_${VERSION}_all.deb
REMOTE

echo "Setup for question 7 completed"
