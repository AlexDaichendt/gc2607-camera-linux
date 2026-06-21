#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKDIR="$(cd "$ROOT/.." && pwd)"
DRIVER="${DRIVER:-${1:-$WORKDIR/gc2607-v4l2-driver}}"
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

for file in gc2607.c Makefile dkms.conf; do
    if [[ ! -f "$DRIVER/$file" ]]; then
        echo "Missing $DRIVER/$file" >&2
        echo "Clone and patch the GC2607 driver repo first, or set DRIVER=/path/to/gc2607-v4l2-driver." >&2
        exit 1
    fi
done

install -d "$SOURCE_DIR"
install -m 0644 "$DRIVER/gc2607.c" "$DRIVER/Makefile" "$DRIVER/dkms.conf" "$SOURCE_DIR/"
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
