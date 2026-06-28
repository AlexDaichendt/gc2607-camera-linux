#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVER="${DRIVER:-${1:-$ROOT/gc2607-kernel}}"
PACKAGE_NAME=gc2607

if [[ "$(id -u)" -ne 0 ]]; then
    cat >&2 <<EOF
Run as root:
  sudo DRIVER="$DRIVER" "$0"
EOF
    exit 1
fi

DRIVER="$(cd "$DRIVER" && pwd)"

for file in "$DRIVER/gc2607.c" "$DRIVER/Makefile" "$DRIVER/dkms.conf"; do
    if [[ ! -f "$file" ]]; then
        echo "Missing $file" >&2
        echo "Expected the GC2607 driver tree (with dkms.conf) under gc2607-kernel/, or set DRIVER=/path/to/driver-tree." >&2
        exit 1
    fi
done

# Version lives in exactly one place: dkms.conf.
PACKAGE_VERSION="$(sed -n 's/^PACKAGE_VERSION="\([^"]*\)".*/\1/p' "$DRIVER/dkms.conf")"
if [[ -z "$PACKAGE_VERSION" ]]; then
    echo "Could not read PACKAGE_VERSION from $DRIVER/dkms.conf" >&2
    exit 1
fi

# Point /usr/src at the in-repo driver tree instead of copying files in.
ln -sfn "$DRIVER" "/usr/src/${PACKAGE_NAME}-${PACKAGE_VERSION}"

# dkms add copies source into /var/lib/dkms at registration time — it does NOT
# re-read from /usr/src on subsequent installs. Always remove+add so the build
# directory reflects the current source tree before installing.
dkms remove -m "$PACKAGE_NAME" -v "$PACKAGE_VERSION" --all 2>/dev/null || true
dkms add -m "$PACKAGE_NAME" -v "$PACKAGE_VERSION"
dkms install -m "$PACKAGE_NAME" -v "$PACKAGE_VERSION"
depmod -a

if lsmod | grep -q "^${PACKAGE_NAME}[[:space:]]"; then
    echo "$PACKAGE_NAME is already loaded; the DKMS-built module will be used after the next reload or reboot."
else
    modprobe "$PACKAGE_NAME"
fi

echo "Installed $PACKAGE_NAME $PACKAGE_VERSION with DKMS and enabled boot-time module loading."
