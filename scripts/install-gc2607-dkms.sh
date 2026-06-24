#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVER="${DRIVER:-${1:-$ROOT/third_party/gc2607-v4l2-driver}}"
PACKAGE_NAME=gc2607
PACKAGE_VERSION=0.1.0
SOURCE_DIR="/usr/src/${PACKAGE_NAME}-${PACKAGE_VERSION}"

if [[ "$(id -u)" -ne 0 ]]; then
    cat >&2 <<EOF
Run as root:
  sudo DRIVER="$DRIVER" "$0"
EOF
    exit 1
fi

# The upstream driver tree does not ship a dkms.conf. Prefer one from the driver
# tree if it exists, otherwise fall back to the dkms.conf bundled with this repo.
DKMS_CONF="${DKMS_CONF:-$DRIVER/dkms.conf}"
if [[ ! -f "$DKMS_CONF" ]]; then
    DKMS_CONF="$ROOT/config/dkms/gc2607-dkms.conf"
fi

for file in "$DRIVER/gc2607.c" "$DRIVER/Makefile" "$DKMS_CONF"; do
    if [[ ! -f "$file" ]]; then
        echo "Missing $file" >&2
        echo "Clone and patch the GC2607 driver repo first, or set DRIVER=/path/to/gc2607-v4l2-driver." >&2
        exit 1
    fi
done

install -d "$SOURCE_DIR"
install -m 0644 "$DRIVER/gc2607.c" "$DRIVER/Makefile" "$SOURCE_DIR/"
install -m 0644 "$DKMS_CONF" "$SOURCE_DIR/dkms.conf"
install -D -m 0644 "$ROOT/config/modules-load.d/gc2607.conf" /etc/modules-load.d/gc2607.conf

if ! dkms status -m "$PACKAGE_NAME" -v "$PACKAGE_VERSION" >/dev/null 2>&1; then
    dkms add -m "$PACKAGE_NAME" -v "$PACKAGE_VERSION"
fi

dkms build -m "$PACKAGE_NAME" -v "$PACKAGE_VERSION"
dkms install -m "$PACKAGE_NAME" -v "$PACKAGE_VERSION" --force
depmod -a

if lsmod | grep -q "^${PACKAGE_NAME}[[:space:]]"; then
    echo "$PACKAGE_NAME is already loaded; the DKMS-built module will be used after the next reload or reboot."
else
    modprobe "$PACKAGE_NAME"
fi

echo "Installed $PACKAGE_NAME with DKMS and enabled boot-time module loading."
