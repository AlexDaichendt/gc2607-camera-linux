#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="${KERNEL:-$(uname -r)}"
IPU6_DRIVERS="${IPU6_DRIVERS:-$ROOT/third_party/ipu6-drivers}"
DKMS_NAME="${DKMS_NAME:-ipu6-drivers}"
DKMS_VERSION="${DKMS_VERSION:-0.0.0}"
DKMS_SOURCE_DIR="/usr/src/${DKMS_NAME}-${DKMS_VERSION}"
TMP_SOURCE=""

cleanup() {
    if [[ -n "$TMP_SOURCE" ]]; then
        rm -rf "$TMP_SOURCE"
    fi
}
trap cleanup EXIT

if [[ ! -f "$IPU6_DRIVERS/dkms.conf" ]]; then
    cat >&2 <<EOF
Missing ipu6-drivers DKMS source:
  $IPU6_DRIVERS/dkms.conf

Run "$ROOT/scripts/clone-sources.sh" first, or set IPU6_DRIVERS=/path/to/ipu6-drivers.
EOF
    exit 1
fi

if ! command -v dkms >/dev/null 2>&1; then
    echo "Missing dkms. Install DKMS with your distro package manager, then rerun this script." >&2
    exit 1
fi

prepare_dkms_source() {
    if git -C "$IPU6_DRIVERS" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        TMP_SOURCE="$(mktemp -d)"
        git -C "$IPU6_DRIVERS" archive --format=tar HEAD | tar -xf - -C "$TMP_SOURCE"
        printf '%s\n' "$TMP_SOURCE"
    else
        printf '%s\n' "$IPU6_DRIVERS"
    fi
}

if [[ ! -f "$DKMS_SOURCE_DIR/dkms.conf" ]]; then
    dkms_add_source="$(prepare_dkms_source)"
    sudo dkms add "$dkms_add_source"
fi

sudo dkms build "$DKMS_NAME/$DKMS_VERSION" -k "$KERNEL"
sudo dkms install "$DKMS_NAME/$DKMS_VERSION" -k "$KERNEL"
sudo depmod -a "$KERNEL"

sudo install -D -m 0644 \
    "$ROOT/config/modules-load.d/intel-ipu6-psys.conf" \
    /etc/modules-load.d/intel-ipu6-psys.conf

sudo install -D -m 0644 \
    "$ROOT/config/udev/rules.d/70-ipu6-psys.rules" \
    /etc/udev/rules.d/70-ipu6-psys.rules

sudo udevadm control --reload-rules

if [[ -e /dev/ipu-psys0 ]]; then
    sudo chgrp video /dev/ipu-psys0 || true
    sudo chmod 660 /dev/ipu-psys0 || true
fi

cat <<EOF
Installed $DKMS_NAME/$DKMS_VERSION for kernel $KERNEL.

The DKMS-managed PSYS module will be used after reboot, or after all camera users are
closed and the live module can be unloaded/reloaded.
EOF
