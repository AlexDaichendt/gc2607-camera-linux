#!/usr/bin/env bash
#
# install-ipu-bridge-dkms.sh
#
# Build and install a patched ipu-bridge.ko that adds the GC2607 sensor ACPI
# HID (GCTI2607). The distro ipu-bridge module lacks this entry; after a kernel
# upgrade the old override is lost, which is why the camera stops working.
#
# After installation, reload the module so the new bridge takes effect without
# a full reboot:
#
#   sudo ./scripts/install-ipu-bridge-dkms.sh --reload
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="${KERNEL:-$(uname -r)}"
SRC="$ROOT/ipu-bridge-gc2607"
DKMS_NAME="ipu-bridge-gc2607"
DKMS_VERSION="0.1.0"
DKMS_SOURCE_DIR="/usr/src/${DKMS_NAME}-${DKMS_VERSION}"
RELOAD="${1:-}"

if ! command -v dkms >/dev/null 2>&1; then
    echo "Missing dkms. Install DKMS with your distro package manager, then rerun." >&2
    exit 1
fi

if [[ ! -f "$SRC/dkms.conf" ]]; then
    echo "Missing source: $SRC/dkms.conf" >&2
    exit 1
fi

if [[ ! -f "$DKMS_SOURCE_DIR/dkms.conf" ]]; then
    sudo cp -r "$SRC" "$DKMS_SOURCE_DIR"
fi

sudo dkms build   "$DKMS_NAME/$DKMS_VERSION" -k "$KERNEL"
sudo dkms install "$DKMS_NAME/$DKMS_VERSION" -k "$KERNEL" --force
sudo depmod -a "$KERNEL"

echo "Installed $DKMS_NAME/$DKMS_VERSION for kernel $KERNEL."

if [[ "$RELOAD" == "--reload" ]]; then
    echo "Reloading ipu-bridge (will also reload dependent modules)..."
    # Unload in reverse dependency order, then reload
    sudo modprobe -r gc2607 intel_ipu6_isys intel_ipu6_psys intel_ipu6 ipu_bridge 2>/dev/null || true
    sudo modprobe ipu_bridge
    sudo modprobe intel_ipu6
    sudo modprobe intel_ipu6_isys
    sudo modprobe intel_ipu6_psys
    sudo modprobe gc2607
    echo "Modules reloaded. Check dmesg and 'media-ctl --print-topology' for the GC2607 node."
else
    cat <<EOF

To apply without rebooting, run:
  sudo $0 --reload

Or reboot and the patched ipu-bridge will load automatically on next boot.
EOF
fi
